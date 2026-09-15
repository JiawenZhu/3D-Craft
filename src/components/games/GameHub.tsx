import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowLeft, ArrowRight, ArrowUp, ArrowDown, Box, Crosshair, Flag, Flame, Gamepad2, Globe2, Maximize, Pause, Play, RotateCcw, Sparkles, Volume2, VolumeX, X, Zap, Coins, Swords, Shield, Orbit, Heart, Footprints } from 'lucide-react';
import { cn } from '../../lib/cn';
import './games.css';
import type { CustomGameAsset } from '../../lib/gameAssets';
import { translator, runtimeText, type GameLocale, type Translate } from './i18n';

export const getGames = (t: Translate) => [
  { id: 'arena', title: 'Emberfront', subtitle: t('装甲竞技场'), category: t('战车对战'), color: '#edab73', description: t('把你的创作开上战场。驾驶装甲车、击败 AI 战车，让油桶的连锁爆炸改变战局。'), objective: t('击败 4 台敌方战车'), controls: t('WASD 驾驶 · 空格开火 · Shift 加速'), assets: [t('小黄车'), t('露营车'), t('机器人'), t('龙'), t('城堡')], image: '/games/covers/arena.jpg' },
  { id: 'race', title: 'Coastline Rush', subtitle: t('小车快跑'), category: t('物理竞速'), color: '#99d7cf', description: t('日落、海风和一个不太安分的后备箱。与 3 台 AI 赛车竞速，越过坡道，撞飞路障。'), objective: t('150 秒内按顺序通过 8 个检查点'), controls: t('WASD 驾驶 · 空格刹车 · Shift 加速'), assets: [t('小黄车'), t('露营车'), t('小屋'), t('熔岩方块')], image: '/games/covers/race.jpg' },
  { id: 'ruins', title: 'The Last Signal', subtitle: t('遗迹回声'), category: t('探索与解谜'), color: '#b6c7ab', description: t('带着你的角色走进被遗忘的遗迹。推动实物机关、恢复三个信号，让古老的城门再次开启。'), objective: t('推箱开启城门，收集 3 个信号后返回出口'), controls: t('WASD 移动 · 空格跳跃 · E 互动'), assets: [t('机器人'), t('波霸猫'), t('龙'), t('城堡'), t('小屋')], image: '/games/covers/ruins.jpg' },
  { id: 'survivor', title: 'Lanternfall', subtitle: t('灯影夜行'), category: t('猫侠生存冒险'), color: '#f4bb75', description: t('一只小猫，一城夜色。穿梭于灯笼照亮的古镇，收集灵光、组合秘术，在不断涌来的暗影中守住最后的灯火。'), objective: t('点亮 3 座灯台，击败夜巡守卫，在四分钟内驱散黑夜。'), controls: t('WASD 移动 · 空格 / Shift 闪避 · 自动攻击'), assets: [t('新生猫侠'), t('随机升级'), t('暗影军团'), t('夜巡首领')], image: '/games/covers/survivor.jpg' },
  { id: 'dragon', title: 'Emerald Skies', subtitle: t('翡翠龙的天空'), category: t('飞行与火焰'), color: '#abe5a1', description: t('和翡翠幼龙一起守护山谷。奔跑、振翅飞翔、穿越光环，用炽热吐息击碎暗影水晶。'), objective: t('穿越 8 个光环，烧毁 6 颗水晶，然后降落回家'), controls: t('WASD 移动 · 空格上升 · C 下降 · F 喷火 · Shift 冲刺'), assets: [t('翡翠幼龙'), t('城堡'), t('火焰吐息'), t('自由飞行')], image: '/games/covers/dragon.jpg' },
] as const;
export type Game = ReturnType<typeof getGames>[number];
type SurvivorChoice = {id:string;name:string;description:string;rank:number};
type SurvivorState = {level:number;xp:number;nextXp:number;kills:number;coins:number;dash:number;choices:SurvivorChoice[];weapons:Record<string,number>;shrines:number;bossHealth:number;bossMaxHealth:number;bossSpawned:boolean};
type State = { customAsset?: {status:'waiting'|'loading'|'ready'|'error';id:string;name:string;error:string}; survivor?: SurvivorState; dragon?: {flying:boolean;fuel:number;recharging:boolean;points:number;combo:number;targets:number[][]}; aim?: number[]; heading?: number; actors?: number[][]; objectives?: number[][]; countdown: number; mode: string; status: string; elapsed: number; speed: number; health: number; score: number; target: number; checkpoint: number; place: number; notice: string; hint: string; gateOpen: boolean; collisions: number; explosions: number; spawned: number; fps: number; position: number[] };
const getVehicles = (t: Translate) => [
  { id: 'scout', name: 'Spark', subtitle: t('敏捷侦察车'), image: '/images/explore/rodin_clean_taxi_1788235881061.jpg' },
  { id: 'heavy', name: 'Nomad', subtitle: t('重型装甲露营车'), image: '/images/explore/rodin_retro_van_1788235619578.jpg' },
  { id: 'cat', name: 'Boba', subtitle: t('波霸猫特制战车'), image: '/images/explore/rodin_boba_cat_1788235650982.jpg' },
];

export function GameHub() {
  const [locale,setLocale] = useState<GameLocale>(()=>{try{return localStorage.getItem('forma-game-language')==='zh'?'zh':'en';}catch{return 'en';}});
  const t=translator(locale);
  const games=getGames(t);
  const [selectedId,setSelectedId]=useState<string|null>(null);
  const selected=games.find(g=>g.id===selectedId)??null;
  const setSelected=(game:Game|null)=>setSelectedId(game?.id??null);
  const changeLocale=(value:GameLocale)=>{setLocale(value);try{localStorage.setItem('forma-game-language',value);}catch{}};
  const [vehicle, setVehicle] = useState('scout');
  const [playing, setPlaying] = useState(false);
  const setup = useRef<HTMLDialogElement>(null);
  useEffect(() => { if (selected && !playing) setup.current?.showModal(); }, [selectedId, playing]);
  return <div className="game-hub" lang={locale==='zh'?'zh-CN':'en'}>
    <div className="game-intro"><div><h2>{t('在这里创作，在这里畅玩。')}</h2><p>{t('从 Explore 到真正的游戏世界。选择一个场景，亲手试试你的 3D 创作。')}</p></div><div className="game-intro-tools"><span><Gamepad2 size={16}/> {t('5 个可玩场景')}</span><LanguageSwitch locale={locale} onChange={changeLocale}/></div></div>
    <div className="game-grid">{games.map(game => <button key={game.id} className="game-card" onClick={() => {setSelected(game); setVehicle('scout');}} style={{'--game-accent':game.color} as React.CSSProperties}>
      <div className="game-cover"><img src={game.image} alt={`${game.title} ${t('实际游戏画面')}`} onError={e => {e.currentTarget.style.visibility='hidden';}}/><span className="game-card-play"><Play size={22} fill="currentColor"/></span><div className="game-cover-title">{game.title}</div></div>
      <div className="game-card-body"><span className="game-category">{game.category}</span><div className="game-card-heading"><h3>{game.subtitle}</h3><ArrowRight size={20}/></div><p>{game.description}</p><div className="game-asset-list">{game.assets.slice(0,4).map(a=><span key={a}>{a}</span>)}</div></div>
    </button>)}</div>
    <p className="game-footnote"><Sparkles size={14}/> {t('真实的 Explore 模型，现在可以驾驶、碰撞和探索。')}</p>
    {selected && !playing && createPortal(<dialog lang={locale==='zh'?'zh-CN':'en'} ref={setup} className="game-setup-backdrop" onCancel={()=>setSelected(null)} aria-labelledby="game-setup-title" onClick={e=>{if(e.target===e.currentTarget)setSelected(null);}}><section className="game-setup">
      <button className="game-close" aria-label={t('关闭游戏选择')} onClick={()=>setSelected(null)}><X/></button><span className="game-category">{selected.category}</span><h2 id="game-setup-title">{selected.title}</h2><p>{selected.description}</p>
      {selected.id==='survivor'?<div className="game-dragon-intro game-cat-intro"><img src="/images/explore/lantern_cat.png" alt={t('新生猫侠')}/><div><h3>{t('灯火的守护者')}</h3><p>{t('九条命的勇气，一盏灯的希望。')}</p><small>{t('攻击会自动瞄准。收集灵光升级，靠近灯台点亮它们。两分钟后首领现身；闪避让你短暂无敌。')}</small></div></div>:selected.id==='dragon'?<div className="game-dragon-intro"><img src="/images/explore/rodin_clean_dragon_1788235904609.jpg" alt={t('翡翠幼龙')}/><div><h3>Baby Emerald Dragon</h3><p>{t('小小的翅膀，大大的冒险。')}</p><small>{t('按住空格起飞；松开后悬停。C 下降并着陆。光环会恢复生命与火焰能量。')}</small></div></div>:<><h3>{selected.id==='ruins'?t('选择你的探险伙伴'):t('选择你的座驾')}</h3><div className="game-vehicles">{getVehicles(t).filter(v=>selected.id!=='ruins'||v.id!=='heavy').map(v=><button key={v.id} aria-pressed={vehicle===v.id} className={cn('game-vehicle',vehicle===v.id&&'selected')} onClick={()=>setVehicle(v.id)}><img src={selected.id==='ruins'&&v.id==='scout'?'/images/explore/rodin_clean_mech.jpg':v.image} alt=""/><strong>{selected.id==='ruins'&&v.id==='scout'?'Orbit':v.name}</strong><small>{selected.id==='ruins'?(v.id==='scout'?t('球形机器人'):t('波霸猫伙伴')):v.subtitle}</small></button>)}</div></>}
      <div className="game-mission"><Flag size={17}/><span>{selected.objective}<small>{selected.controls}{selected.id!=='survivor'&&<> · R {t('回到安全位置')}</>}</small></span></div><button className="game-start" onClick={()=>setPlaying(true)}><Play size={18} fill="currentColor"/> {t('开始游戏')}</button><p className="game-setup-note">{t('首次加载需要下载游戏和模型。支持键盘，也提供触屏控制。')}</p>
    </section></dialog>,document.body)}
    {selected && playing && <GamePlayer game={selected} vehicle={vehicle} locale={locale} onLocaleChange={changeLocale} onClose={()=>{setPlaying(false);setSelected(null);}}/>}
  </div>;
}

export function GamePlayer({game,vehicle,locale,onLocaleChange,onClose,customAsset}:{game:Game;vehicle:string;locale:GameLocale;onLocaleChange:(locale:GameLocale)=>void;onClose:()=>void;customAsset?:CustomGameAsset}) {
  const t=translator(locale);
  const initialLocale=useRef(locale);
  const frame=useRef<HTMLIFrameElement>(null);
  const root=useRef<HTMLDivElement>(null);
  const [state,setState]=useState<State|null>(null);
  const [failed,setFailed]=useState('');
  const [mute,setMute]=useState(false);
  const [session,setSession]=useState(0);
  const loadedSession=useRef<number|null>(null);
  const [best,setBest]=useState<number|null>(()=>{try {return Number(localStorage.getItem(`forma-game-best-${game.id}`))||null;}catch{return null;}});
  const send=(action:string,extra:Record<string,unknown>={})=>frame.current?.contentWindow?.postMessage({channel:'forma-game',action,...extra},window.location.origin);
  useEffect(()=>{
    const previous=document.body.style.overflow; document.body.style.overflow='hidden';
    const app=document.getElementById('root');
    const previousInert=app?.inert??false;
    if(app)app.inert=true;
    const receive=(event:MessageEvent)=>{
      if(event.origin!==window.location.origin||event.source!==frame.current?.contentWindow)return;
      if(event.data?.channel==='forma-state')setState(event.data);
      if(event.data?.channel==='forma-error')setFailed(event.data.message||'游戏启动失败，请重新加载。');
    };
    const release=()=>send('release');
    const heldKeys: Record<string,string> = {w:'forward',ArrowUp:'forward',s:'back',ArrowDown:'back',a:'left',ArrowLeft:'left',d:'right',ArrowRight:'right',Shift:'boost',' ':game.id==='survivor'?'dash':game.id==='dragon'?'ascend':game.id==='arena'?'fire':game.id==='race'?'brake':'jump',...(game.id==='dragon'?{f:'fire',c:'descend'}:{})};
    const keys=(e:KeyboardEvent)=>{
      const key=e.key.length===1?e.key.toLowerCase():e.key;
      if(key===' '&&(e.target as HTMLElement)?.closest('button'))return;
      if(heldKeys[key]){e.preventDefault();send('input',{key:heldKeys[key],down:true});return;}
      if(e.repeat)return;
      const action=key==='Escape'||key==='p'?'pause':key==='r'&&game.id!=='survivor'?'recover':key==='q'&&game.id!=='survivor'?'crate':key==='e'&&game.id!=='survivor'?(game.id==='ruins'?'interact':'barrel'):null;
      if(action){e.preventDefault();send(action);}
    };
    const keyup=(e:KeyboardEvent)=>{const key=e.key.length===1?e.key.toLowerCase():e.key;if(heldKeys[key])send('input',{key:heldKeys[key],down:false});};
    const hidden=()=>{if(document.hidden)release();};
    window.addEventListener('message',receive);window.addEventListener('blur',release);window.addEventListener('keydown',keys);window.addEventListener('keyup',keyup);document.addEventListener('visibilitychange',hidden);
    return()=>{document.body.style.overflow=previous;if(app)app.inert=previousInert;window.removeEventListener('message',receive);window.removeEventListener('blur',release);window.removeEventListener('keydown',keys);window.removeEventListener('keyup',keyup);document.removeEventListener('visibilitychange',hidden);};
  },[session]);
  useEffect(()=>{if(state?.status==='won'&&(!best||state.elapsed<best)){setBest(state.elapsed);try{localStorage.setItem(`forma-game-best-${game.id}`,String(state.elapsed));}catch{}}},[state?.status,state?.elapsed,best,game.id]);
  useEffect(()=>{const timer=setTimeout(()=>{if(!state)setFailed('加载时间较长。请检查连接，或重新加载游戏。');},90000);return()=>clearTimeout(timer);},[!!state,session]);
  useEffect(()=>{if(state)send('language',{value:locale});},[locale,!!state]);
  useEffect(()=>{if(customAsset&&state?.customAsset?.status==='waiting'&&loadedSession.current!==session){loadedSession.current=session;send('load_asset',{asset:customAsset});}},[customAsset,state?.customAsset?.status,session]);
  useEffect(()=>{if(!customAsset||!state||state.customAsset?.status==='ready'||state.customAsset?.status==='error')return;const timer=setTimeout(()=>setFailed('模型加载时间较长。请重试或返回模型查看器。'),120000);return()=>clearTimeout(timer);},[!!customAsset,!!state,state?.customAsset?.status,session]);
  const customReady=!customAsset||state?.customAsset?.status==='ready';
  const loadError=failed||(customAsset&&state?.customAsset?.status==='error'?(state.customAsset.error||t('无法加载此模型。请重试。')):'');
  const restart=()=>{initialLocale.current=locale;setState(null);setFailed('');setMute(false);setSession(s=>s+1);};
  const held=(key:string)=>({onPointerDown:(e:React.PointerEvent<HTMLButtonElement>)=>{e.currentTarget.setPointerCapture(e.pointerId);send('input',{key,down:true});},onPointerUp:()=>send('input',{key,down:false}),onPointerCancel:()=>send('input',{key,down:false}),onLostPointerCapture:()=>send('input',{key,down:false})});
  const clock=(seconds:number)=>`${Math.floor(seconds/60).toString().padStart(2,'0')}:${(seconds%60).toFixed(1).padStart(4,'0')}`;
  return createPortal(<div ref={root} role="dialog" aria-modal="true" aria-label={`${game.title} ${t('游戏')}`} className={cn("game-player",game.id==='survivor'&&'game-player-survivor')} lang={locale==='zh'?'zh-CN':'en'} style={{'--game-accent':game.color} as React.CSSProperties}>
    <iframe key={session} ref={frame} className="game-frame" title={`${game.title} Godot 3D game`} src={`/games/forma/index.html?mode=${game.id}&vehicle=${vehicle}&lang=${initialLocale.current}${customAsset?'&custom=1':''}`} allow="autoplay; fullscreen; gamepad" onLoad={()=>frame.current?.focus()}/>
    <div className="game-hud-top"><button onClick={onClose} aria-label={t('退出游戏')}><ArrowLeft size={18}/><span>Game</span></button><div className="game-name"><strong>{game.title}</strong><small>{customAsset?`${t('当前角色')} ${customAsset.name}`:game.subtitle}</small></div><div className="game-hud-actions"><LanguageSwitch locale={locale} onChange={onLocaleChange}/><button onClick={()=>{send('mute',{value:!mute});setMute(!mute);}} aria-label={mute?t('开启声音'):t('关闭声音')}>{mute?<VolumeX size={17}/>:<Volume2 size={17}/>}</button><button className="game-fullscreen" onClick={()=>root.current?.requestFullscreen().catch(()=>{})} aria-label={t('全屏')}><Maximize size={17}/></button><button onClick={()=>{send('pause');frame.current?.focus();}} aria-label={t('暂停或继续')}>{state?.status==='paused'?<Play size={17}/>:<Pause size={17}/>}</button><button onClick={restart} aria-label={t('重新开始')}><RotateCcw size={17}/></button></div></div>
    {state && customReady && <>{state.countdown>0&&<div className="game-countdown" aria-live="polite"><span>{t('准备出发')}</span><strong>{state.countdown}</strong></div>}{game.id==='survivor'?<SurvivorHud state={state} locale={locale} t={t} customAsset={customAsset}/>:<div className="game-objective"><span>{game.id==='dragon'?t('守护翡翠山谷'):game.id==='arena'?t('清除敌方战车'):game.id==='race'?t('环岛计时赛'):t('恢复遗迹信号')}</span><strong>{game.id==='race'?clock(state.elapsed):`${state.score} / ${state.target}`}</strong><small>{game.id==='dragon'?`${t('光环')} ${state.checkpoint} / 8 · ${t('生命')} ${state.health}%`:game.id==='race'?`${t('检查点')} ${state.checkpoint} / 8 · ${t('排名')} ${state.place} / 4`:game.id==='ruins'?(state.gateOpen?t('城门已开启'):t('推箱触发地面的封印')):`${t('装甲')} ${state.health}%`}</small></div>}
    {game.id==='dragon'&&<div className="game-dragon-status"><span>{state.dragon?.flying?t('飞行中'):t('地面奔跑')} · {Math.max(0,Math.round(state.position[1]-1))} m</span><strong>{state.dragon?.points??0} <small>{t('得分')}</small></strong><label><Flame size={14}/> {state.dragon?.recharging?t('火焰恢复中'):t('火焰能量')} {state.dragon?.fuel??100}%</label><div className="game-fuel"><i style={{width:`${state.dragon?.fuel??100}%`}}/></div>{(state.dragon?.combo??0)>1&&<b>×{state.dragon?.combo} {t('连击')}</b>}{state.checkpoint===8&&state.score===6&&<p>{t('山谷安全了！返回鸟巢，按 C 降落。')}</p>}</div>}
    {game.id!=='ruins'&&game.id!=='dragon'&&game.id!=='survivor'&&<div className="game-speed"><strong>{state.speed}</strong><span>KM/H</span><div><i style={{width:`${Math.min(100,state.health)}%`}}/></div></div>}
    <GameMap game={game} state={state} t={t}/>
    {(game.id==='arena'||game.id==='dragon')&&<div className="game-crosshair" style={{left:`${Math.max(3,Math.min(97,(state.aim?.[0]??.5)*100))}%`,top:`${Math.max(15,Math.min(85,(state.aim?.[1]??.5)*100))}%`}}><Crosshair size={26}/></div>}
    {state.hint&&<button className="game-interact" onClick={()=>send('interact')}>{runtimeText(state.hint,locale)}</button>}
    <output className="game-telemetry" aria-label={t('游戏状态')} data-state={JSON.stringify(state)}>{state.fps} FPS · {state.collisions} {t('碰撞')} · {state.explosions} {t('爆炸')}</output></>}
    {customReady&&<div className="game-controls"><div className="game-dpad"><button {...held('forward')} aria-label={t('前进')}><ArrowUp size={20}/></button><div><button {...held('left')} aria-label={t('左转')}><ArrowLeft size={20}/></button><button {...held('back')} aria-label={t('后退')}><ArrowDown size={20}/></button><button {...held('right')} aria-label={t('右转')}><ArrowRight size={20}/></button></div></div><div className="game-control-legend"><span>{game.controls}</span><small>{game.id==='survivor'?t('拾取灵光升级 · 靠近灯台点亮 · 闪避穿越敌群'):game.id==='dragon'?t('穿环补充能量 · 连续击碎水晶获得连击奖励'):< >Q {t('生成物体')} · {game.id==='ruins'?t('E 互动'):t('E 生成油桶')}</>}{game.id!=='survivor'&&<> · R {t('复位')}</>} · P {t('暂停')}</small></div><div className="game-abilities">{game.id==='survivor'?<button className="game-primary-action game-dash-action" {...held('dash')} title={t('闪避 (空格 / Shift)')}><Zap size={19}/><span>{t('闪避')}</span><small>{(state?.survivor?.dash??1)>=1?t('就绪'):`${Math.round((state?.survivor?.dash??0)*100)}%`}</small></button>:<>{game.id==='dragon'?<><button {...held('descend')} title={t('下降并着陆 (C)')}><ArrowDown size={18}/>{t('下降')}</button><button {...held('ascend')} title={t('起飞与上升 (空格)')}><ArrowUp size={18}/>{t('上升')}</button></>:<><button onClick={()=>send('crate')} title={t('生成熔岩方块 (Q)')}><Box size={19}/><span>{t('物体')}</span></button>{game.id!=='ruins'&&<button onClick={()=>send('barrel')} title={t('生成爆炸桶 (E)')}><span>{t('油桶')}</span></button>}</>}<button {...held('boost')} title={t('加速 (Shift)')} aria-label={t('加速')}><Sparkles size={18}/></button><button className="game-primary-action" {...held(game.id==='dragon'||game.id==='arena'?'fire':game.id==='race'?'brake':'jump')}>{game.id==='dragon'?<><Flame size={19}/>{t('喷火')}</>:game.id==='arena'?t('开火'):game.id==='race'?t('刹车'):t('跳跃')}</button></>}</div></div>}
    {state&&!customReady&&<output className="game-telemetry" aria-label={t('游戏状态')} data-state={JSON.stringify(state)}/> }
    {(!state||loadError||!customReady)&&<div className="game-loading">{loadError?<Box size={35}/>:<div className="game-spinner"/>}<h2>{loadError?t('暂时无法进入'):customAsset?`${t('正在带入')} ${customAsset.name}`:`${t('正在进入')} ${game.title}`}</h2><p>{loadError?runtimeText(t(loadError),locale):customAsset?t('正在加载你的真实 3D 模型。准备好后，游戏才会开始。'):t('正在加载 Godot 引擎与 Explore 的真实 3D 模型…')}</p>{loadError&&<button className="game-start" onClick={restart}>{t('重新加载')}</button>}<button onClick={onClose}>{customAsset?t('返回模型'):t('返回 Game')}</button></div>}
    {customReady&&state?.status==='upgrading'&&state.survivor&&<UpgradePicker choices={state.survivor.choices} level={state.survivor.level} locale={locale} t={t} onChoose={index=>{send('upgrade',{index});frame.current?.focus();}}/>}
    {customReady&&state&&state.status!=='playing'&&state.status!=='upgrading'&&<div className="game-result"><section><span>{state.status==='paused'?t('已暂停'):state.status==='won'?t('已完成'):t('再试一次')}</span><h2>{state.status==='paused'?t('休息一下'):state.status==='won'?t('完成挑战'):t('再来一局')}</h2><p>{state.status==='paused'?game.objective:runtimeText(state.notice,locale)}</p>{state.status==='won'&&<strong>{clock(state.elapsed)} {best&&<small>{t('个人最佳')} {clock(best)}</small>}</strong>}<button className="game-start" onClick={()=>{if(state.status==='paused'){send('pause');frame.current?.focus();}else restart();}}>{state.status==='paused'?t('继续游戏'):t('再玩一次')}</button><button onClick={onClose}>{customAsset?t('返回模型'):t('选择其他游戏')}</button></section></div>}
  </div>,document.body);
}

function GameMap({game,state,t}:{game:Game;state:State;t:Translate}) {
  const scale=game.id==='survivor'?1.35:game.id==='dragon'?.9:game.id==='ruins'?2.8:1.35;
  const point=(x:number,z:number)=>[60+x*scale,60+z*scale];
  const [px,py]=point(state.position[0],state.position[2]);
  return <div className="game-minimap"><span>{game.id==='survivor'?t('古镇'):game.id==='dragon'?t('山谷'):game.id==='arena'?t('战场'):game.id==='race'?t('赛道'):t('遗迹')}</span><svg viewBox="0 0 120 120" role="img" aria-label={t('当前位置与目标地图')}>
    {game.id==='race'?<ellipse cx="60" cy="60" rx={26*scale} ry={18*scale} fill="none" stroke="#c2d4cd40" strokeWidth={10*scale}/>:<rect x={game.id==='ruins'?20.8:15.45} y={game.id==='ruins'?15.2:15.45} width={game.id==='ruins'?78.4:89.1} height={game.id==='ruins'?89.6:89.1} fill="none" stroke="#c2d4cd50" strokeWidth="1"/>}
    {game.id==='ruins'&&<><path d="M21 66 H39 M48 66 H99" stroke="#a8bfb76e" strokeWidth="2"/><circle cx="60" cy="23.6" r="3.5" fill={state.score===3?'#e9d7aa':'#759088'}/></>}
    {(state.objectives??[]).map(([x,z],i)=>{const [cx,cy]=point(x,z);const active=(game.id!=='race'&&game.id!=='dragon')||i===state.checkpoint;return <circle key={i} cx={cx} cy={cy} r={active?3.5:1.6} fill={active?(game.id==='dragon'||game.id==='survivor'?'#ffe5ac':'#a0ecdd'):'#d4dcdc60'}/>;})}
    {game.id==='dragon'&&<><circle cx="60" cy="87.9" r="3.5" fill="#ffe5ac"/>{(state.dragon?.targets??[]).map(([x,z],i)=>{const [cx,cy]=point(x,z);return <circle key={i} cx={cx} cy={cy} r="3" fill="#dc9cf2"/>;})}</>}
    {(state.actors??[]).map(([x,z],i)=>{const [cx,cy]=point(x,z);return <circle key={i} cx={cx} cy={cy} r="2.3" fill={game.id==='arena'||game.id==='survivor'?'#ef9874':'#e4bb90'}/>;})}
    <g transform={`translate(${px},${py}) rotate(${-(state.heading??0)*180/Math.PI})`}><path d="M0 -5 L3.7 3.5 L0 2 L-3.7 3.5 Z" fill="#fcfaf0" stroke="#1c3538" strokeWidth=".7"/></g>
  </svg><small>{game.id==='survivor'?t('金色 · 灯台 / 红色 · 暗影'):game.id==='dragon'?t('金色 · 下个光环 / 紫色 · 水晶'):game.id==='arena'?t('橙色 · 敌方战车'):game.id==='race'?t('亮点 · 下个检查点'):t('亮点 · 未恢复信号')}</small></div>;
}

export function LanguageSwitch({locale,onChange}:{locale:GameLocale;onChange:(locale:GameLocale)=>void}) {
  return <button type="button" className="game-language-toggle" aria-label={locale==='en'?'Switch to Chinese':'切换为英语'} onClick={()=>onChange(locale==='en'?'zh':'en')}><Globe2 size={14}/><span>{locale==='en'?'中文':'EN'}</span></button>;
}

const weaponIcons: Record<string,typeof Zap> = {bolt:Zap,orbit:Orbit,pulse:Shield,vitality:Heart,haste:Footprints};
const weaponLabels: Record<string,string> = {bolt:'灵火符',orbit:'月轮刃',pulse:'灯火爆发',vitality:'九命护佑',haste:'丝影步'};
function SurvivorHud({state,locale,t,customAsset}:{state:State;locale:GameLocale;t:Translate;customAsset?:CustomGameAsset}) {
  const run=state.survivor;
  if(!run)return null;
  const health=Math.max(0,Math.min(100,state.health));
  const xp=Math.max(0,Math.min(100,run.xp/Math.max(1,run.nextXp)*100));
  const seconds=Math.max(0,Math.floor(state.elapsed));
  return <>
    <div className="game-survivor-vitals" aria-label={t('猫侠状态')}>
      {customAsset?(customAsset.thumbUrl?<img src={customAsset.thumbUrl} alt=""/>:<div className="game-custom-portrait"><Box size={24}/></div>):<img src="/images/explore/lantern_cat.png" alt=""/>}
      <div className="game-survivor-bars"><div><b>{t('等级')} {run.level}</b><span>{t('生命')} {health}%</span></div><div className="game-survivor-meter game-health-meter" role="progressbar" aria-label={t('生命')} aria-valuenow={health} aria-valuemin={0} aria-valuemax={100}><i style={{width:`${health}%`}}/></div><div className="game-survivor-meter game-xp-meter" role="progressbar" aria-label={t('灵光')} aria-valuenow={run.xp} aria-valuemin={0} aria-valuemax={run.nextXp}><i style={{width:`${xp}%`}}/></div><small>{t('灵光')} {run.xp} / {run.nextXp}</small></div>
      <div className="game-survivor-tallies"><span><Swords size={13}/>{run.kills} <small>{t('击退')}</small></span><span><Coins size={13}/>{run.coins} <small>{t('铜钱')}</small></span></div>
    </div>
    <div className="game-survivor-clock"><strong>{String(Math.floor(seconds/60)).padStart(2,'0')}:{String(seconds%60).padStart(2,'0')}</strong><span>{run.bossSpawned?t('夜巡已至'):t('夜色渐深')}</span><small>{t('灯台')} {run.shrines} / 3</small></div>
    {run.bossSpawned&&run.bossHealth>0&&<div className="game-survivor-boss"><span>{t('夜巡守卫')}</span><div role="progressbar" aria-label={t('首领生命')} aria-valuenow={Math.ceil(run.bossHealth)} aria-valuemin={0} aria-valuemax={run.bossMaxHealth}><i style={{width:`${Math.max(0,Math.min(100,run.bossHealth/Math.max(1,run.bossMaxHealth)*100))}%`}}/></div></div>}
    <div className="game-survivor-weapons" aria-label={t('当前秘术')}>{['bolt','orbit','pulse'].map(id=>{const Icon=weaponIcons[id];const rank=run.weapons[id]??0;return <div key={id} className={cn('game-weapon-slot',!rank&&'locked')} title={`${t(weaponLabels[id])} · ${t('等级')} ${rank}`}><Icon size={23}/><span>{t(weaponLabels[id])}</span><small>{rank?`${t('等级')} ${rank}`:t('未解锁')}</small></div>;})}</div>
    {state.notice&&state.status==='playing'&&<div className="game-survivor-notice" role="status">{runtimeText(state.notice,locale)}</div>}
  </>;
}

function UpgradePicker({choices,level,locale,t,onChoose}:{choices:SurvivorChoice[];level:number;locale:GameLocale;t:Translate;onChoose:(index:number)=>void}) {
  const first=useRef<HTMLButtonElement>(null);
  useEffect(()=>{first.current?.focus();},[level]);
  return <div className="game-upgrade-overlay" role="dialog" aria-modal="true" aria-labelledby="game-upgrade-title"><section><span className="game-upgrade-eyebrow"><Sparkles size={16}/>{t('等级')} {level}</span><h2 id="game-upgrade-title">{t('让灯火更亮一些。')}</h2><p>{t('选择一项秘术。时间已暂停，慢慢挑选。')}</p><div className="game-upgrade-options">{choices.map((choice,index)=>{const Icon=weaponIcons[choice.id]??Sparkles;return <button key={choice.id} ref={index===0?first:undefined} onClick={()=>onChoose(index)}><span className="game-upgrade-icon"><Icon size={30}/></span><small>{t('等级')} {choice.rank}</small><h3>{weaponLabels[choice.id]?t(weaponLabels[choice.id]):runtimeText(choice.name,locale)}</h3><p>{runtimeText(choice.description,locale)}</p><span className="game-upgrade-select">{t('选择秘术')}<ArrowRight size={15}/></span></button>;})}</div></section></div>;
}
