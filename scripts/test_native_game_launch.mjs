import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import ts from 'typescript';
import { pathToFileURL } from 'node:url';
const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'craft-native-game-'));
try {
  for (const name of ['gameAssetRules','nativeGameLaunch']) {
    const source = await fs.readFile(`src/lib/${name}.ts`, 'utf8');
    const out = ts.transpileModule(source, {compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.ESNext}}).outputText.replace("'./gameAssetRules'", "'./gameAssetRules.mjs'");
    await fs.writeFile(path.join(dir, name + '.mjs'), out);
  }
  const {decodeNativeGameLaunch} = await import(pathToFileURL(path.join(dir, 'nativeGameLaunch.mjs')));
  const page = 'http://127.0.0.1:3000';
  const payload = {version:1,game:'survivor',locale:'zh',asset:{id:'cat-01',name:'猫侠 Lantern Cat',url:page+'/models/lantern_cat.glb',thumbUrl:page+'/images/explore/lantern_cat.png',kind:'character',yaw:90}};
  const encode = value => '#' + Buffer.from(JSON.stringify(value)).toString('base64');
  const launch = decodeNativeGameLaunch(encode(payload),page);
  assert.equal(launch.asset.id,'cat-01'); assert.equal(launch.asset.name,'猫侠 Lantern Cat'); assert.equal(launch.asset.url,payload.asset.url); assert.equal(launch.asset.yaw,90); assert.equal(launch.locale,'zh');
  const withURL = url => ({...payload,asset:{...payload.asset,url}});
  assert.equal(decodeNativeGameLaunch(encode(withURL('http://127.0.0.1:8000/files/test/model.glb')),page).asset.url,'http://127.0.0.1:8000/files/test/model.glb');
  for(const url of ['https://evil.example/model.glb','file:///tmp/model.glb','http://127.0.0.1:9000/models/cat.glb',page+'/api/delete.glb',page+'/models/cat.glb?token=secret',page+'/models/../api/a.glb','http://user:password@127.0.0.1:3000/models/cat.glb']) assert.throws(()=>decodeNativeGameLaunch(encode(withURL(url)),page));
  assert.throws(()=>decodeNativeGameLaunch(encode(payload),'https://production.example'));
  assert.throws(()=>decodeNativeGameLaunch(encode({...payload,game:'race'}),page));
  assert.throws(()=>decodeNativeGameLaunch(encode({...payload,asset:{...payload.asset,yaw:45}}),page));
  assert.throws(()=>decodeNativeGameLaunch('#not-json',page));
  for(const [kind,games] of [['vehicle',['arena','race']],['character',['survivor','ruins']],['flying',['dragon','survivor','ruins']]]) for(const game of games) assert.equal(decodeNativeGameLaunch(encode({...payload,game,asset:{...payload.asset,kind}}),page).game,game);
  console.log('PASS native game launch: exact model and UTF-8 identity, backend assets, all compatible games, invalid origins/URLs/credentials/directions and malformed payload rejection');
} finally { await fs.rm(dir,{recursive:true,force:true}); }
