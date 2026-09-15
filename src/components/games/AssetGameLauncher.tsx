import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowRight, Box, Car, Footprints, RotateCw, Sparkles, X } from 'lucide-react';
import type { Asset } from '../../types';
import { imageSrc } from '../../lib/api';
import { compatibleGameIds, prepareGameAsset, suggestGameAssetKind, type CustomGameAsset, type GameAssetKind } from '../../lib/gameAssets';
import { GamePlayer, getGames, LanguageSwitch } from './GameHub';
import { translator, runtimeText, type GameLocale } from './i18n';
import { cn } from '../../lib/cn';

export function AssetGameLauncher({asset,locale,onLocaleChange,onClose,onPlayingChange}:{asset:Asset;locale:GameLocale;onLocaleChange:(locale:GameLocale)=>void;onClose:()=>void;onPlayingChange:(playing:boolean)=>void}) {
  const t=translator(locale);
  const [kind,setKind]=useState<GameAssetKind>(()=>suggestGameAssetKind(asset));
  const [yaw,setYaw]=useState(0);
  const [selectedId,setSelectedId]=useState<string|null>(null);
  const [customAsset,setCustomAsset]=useState<CustomGameAsset|null>(null);
  const [error,setError]=useState('');
  const dialog=useRef<HTMLDialogElement>(null);
  const compatible=compatibleGameIds(kind);
  const games=getGames(t).filter(game=>compatible.includes(game.id)).sort((a,b)=>compatible.indexOf(a.id)-compatible.indexOf(b.id));
  const selected=games.find(game=>game.id===selectedId)??games[0];
  useEffect(()=>{if(!customAsset)dialog.current?.showModal();},[!!customAsset]);
  useEffect(()=>()=>onPlayingChange(false),[]);
  const start=()=>{
    try {const made=prepareGameAsset(asset,kind,yaw);setCustomAsset(made);onPlayingChange(true);}
    catch(cause){setError(cause instanceof Error?cause.message:String(cause));}
  };
  if(customAsset&&selected)return <GamePlayer game={selected} vehicle="scout" customAsset={customAsset} locale={locale} onLocaleChange={onLocaleChange} onClose={onClose}/>;
  return createPortal(<dialog ref={dialog} className="game-setup-backdrop" lang={locale==='zh'?'zh-CN':'en'} aria-labelledby="asset-game-title" onCancel={onClose} onClick={event=>{if(event.target===event.currentTarget)onClose();}}><section className="game-setup game-asset-launcher">
    <button className="game-close" aria-label={t('关闭游戏选择')} onClick={onClose}><X size={20}/></button>
    <div className="game-launcher-heading"><span className="game-category">{t('让创作动起来')}</span><LanguageSwitch locale={locale} onChange={onLocaleChange}/></div>
    <h2 id="asset-game-title">{t('带进游戏，亲手试试。')}</h2><p>{t('选择一个世界，让当前的模型成为你的角色。')}</p>
    <div className="game-launcher-asset">{asset.thumbUrl?<img src={imageSrc(asset.thumbUrl)} alt=""/>:<Box size={30}/>}<div><strong>{asset.name}</strong><span>{t('使用当前 3D 模型')}</span></div></div>
    <fieldset className="game-asset-kind"><legend>{t('这是什么类型的模型？')}</legend>{([{id:'vehicle',label:'车辆',Icon:Car},{id:'character',label:'角色',Icon:Footprints},{id:'flying',label:'飞行角色',Icon:Sparkles}] as const).map(({id,label,Icon})=><button key={id} aria-pressed={kind===id} className={cn(kind===id&&'selected')} onClick={()=>{setKind(id);setSelectedId(null);setError('');}}><Icon size={16}/>{t(label)}</button>)}</fieldset>
    <div className="game-launcher-worlds" aria-label={t('选择游戏')}>{games.map(game=><button key={game.id} aria-pressed={selected?.id===game.id} className={cn('game-launcher-world',selected?.id===game.id&&'selected')} onClick={()=>setSelectedId(game.id)}><img src={game.image} alt=""/><span><strong>{game.title}</strong><small>{game.subtitle}</small></span><ArrowRight size={17}/></button>)}</div>
    <details className="game-model-facing"><summary>{t('模型朝向')}<RotateCw size={13}/></summary><p>{t('如果模型在游戏里背对前方，可以调整朝向后再进入。')}</p><div>{([{value:0,label:'原始朝向'},{value:90,label:'向右转'},{value:180,label:'转身'},{value:270,label:'向左转'}]).map(item=><button key={item.value} aria-pressed={yaw===item.value} className={cn(yaw===item.value&&'selected')} onClick={()=>setYaw(item.value)}>{t(item.label)}</button>)}</div></details>
    {error&&<p className="game-launcher-error" role="alert">{runtimeText(error,locale)}</p>}
    <button className="game-start" disabled={!selected||!asset.modelUrl} onClick={start}>{t('进入')} {selected?.title}<ArrowRight size={17}/></button><p className="game-setup-note">{t('保留模型的外观，使用所选游戏的移动方式。')}</p>
  </section></dialog>,document.body);
}
