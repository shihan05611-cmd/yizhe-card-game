/* Presentation-only study. No game-domain code or saved state is consumed. */
(() => {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const scene = $('#scene'), viewport = $('#viewport');
  function fit() {
    const scale = Math.min(innerWidth / 1600, innerHeight / 900);
    viewport.style.height = innerHeight + 'px';
    scene.style.transform = `scale(${scale})`;
    scene.style.marginRight = (1600 * scale - 1600) + 'px';
    scene.style.marginBottom = (900 * scale - 900) + 'px';
  }
  addEventListener('resize', fit); fit();
  const icons = {
    shield:'<path fill="currentColor" fill-opacity=".13" d="M50 12 75 24 71 55 50 72 29 55 25 24Z"/><path d="M50 12 75 24 71 55 50 72 29 55 25 24Z M50 20 66 28 64 52 50 63 36 52 34 28Z M50 22V60 M36 34H64 M20 25 15 45 23 61 M80 25 85 45 77 61"/>',
    ray:'<path fill="currentColor" fill-opacity=".12" d="m50 18 13 24-13 24-13-24Z"/><path d="m50 18 13 24-13 24-13-24Z M50 6V14 M50 70V78 M20 12 29 24 M71 24 80 12 M12 42H29 M71 42H88 M20 72 29 60 M71 60 80 72 M50 28V56 M42 42H58"/>',
    flame:'<path fill="currentColor" fill-opacity=".12" d="M49 8C55 29 78 30 73 52 70 70 39 79 27 58 18 43 35 29 36 21 46 36 48 31 49 8Z"/><path d="M49 8C55 29 78 30 73 52 70 70 39 79 27 58 18 43 35 29 36 21 46 36 48 31 49 8Z M52 38C67 56 56 70 44 65 33 58 47 50 52 38Z M19 60 14 68 M80 56 86 63 M65 17 70 10"/>',
    blade:'<path fill="currentColor" fill-opacity=".12" d="m68 10 7 5-22 37-9-7Z M38 51l10 8-13 17-9-7Z"/><path d="m68 10 7 5-22 37-9-7Z M38 51l10 8-13 17-9-7Z M32 42 58 62 M17 24 32 34 M80 54 91 59 M23 14 36 24 M75 69 83 76 M43 40 61 54"/>',
    motion:'<path fill="currentColor" fill-opacity=".15" d="m49 10 20 6-20 25 12 9-28 24 7-28-9-8Z"/><path d="m49 10 20 6-20 25 12 9-28 24 7-28-9-8Z M18 28H30 M11 39H23 M13 50H25 M63 56H82 M58 67H74 M71 22H86"/>',
    heal:'<path d="M42 14H58V32H76V48H58V66H42V48H24V32H42Z M24 60 17 66 M75 16 82 9 M18 16 24 22 M75 62 81 68"/><path fill="currentColor" fill-opacity=".13" d="M42 14H58V32H76V48H58V66H42V48H24V32H42Z"/>'
  };
  const initialCards = [
    {name:'棋子格挡',cost:1,icon:'shield',description:'全体我方格挡率 <b>+15%</b><br>持续 1 回合',target:'ally',effect:'全体棋子 · 格挡',full:'消耗 1 技能点。全体我方棋子获得 15% 临时格挡率，持续 1 回合。'},
    {name:'棋子增伤',cost:1,icon:'ray',description:'全体直接伤害 <b>+30%</b><br>我方 · 持续 1 回合',target:'ally',effect:'全体棋子 · 增伤',full:'消耗 1 技能点。全体我方棋子直接伤害 +30%，持续 1 回合。'},
    {name:'灼痕标记',cost:0,icon:'flame',description:'敌方灼烧最多的单位<br>施加 <b>1 层灼烧</b>',target:'burn',effect:'灼烧 +1',full:'消耗 0 技能点。对敌方灼烧层数最高的单位施加 1 层灼烧。此概念场景以敌方第一枚甲卒作为示例目标。'},
    {name:'斩杀',cost:2,icon:'blade',description:'我方攻击最高的棋子<br>攻击敌方最低生命单位',target:'low',effect:'斩杀 · 命中',full:'消耗 2 技能点。令我方攻击力最高的棋子立刻攻击敌方当前生命最低的单位。这里只展示命中反馈，不计算实战伤害。'},
    {name:'棋子行动',cost:1,icon:'motion',description:'指定我方棋子<br>下次行动次数 <b>+1</b>',target:'single',effect:'额外行动 +1',full:'消耗 1 技能点。使指定我方棋子在下次行动时额外行动一次。'}
  ];
  const extras = [{...initialCards[0]}, {...initialCards[4]}];
  let cards=[], selected=null, sp=7, discarded=4, round=3, seven=false, speed=1, busy=false;
  let toastTimer, turnTimer, selectionTimer;
  const logs=['第三回合开始。当前为美术概念示例状态。'];
  const names={shield:'甲卒',crossbow:'机弩',assassin:'刺客',banner:'旗兵'};
  const roster=['shield','shield','shield','assassin','crossbow','banner'];
  const alliesHp=[[360,450],[450,450],[328,450],[240,240],[260,300],[300,300]];
  const enemiesHp=[[280,360],[360,360],[316,360],[126,220],[210,260],[260,260]];
  let uid=0;
  function makeCards(){cards=[...initialCards,...(seven?extras:[])].map(c=>({...c,id:++uid}));}
  function buildArmy(enemy){
    const root=enemy?$('#enemies'):$('#allies');
    roster.forEach((kind,index)=>{
      const hp=(enemy?enemiesHp:alliesHp)[index];
      const button=document.createElement('button');
      button.className='piece';button.dataset.side=enemy?'enemy':'ally';button.dataset.index=index;
      button.setAttribute('aria-label',`${enemy?'敌方':'我方'}${index+1}号${names[kind]}，生命 ${hp[0]}/${hp[1]}`);
      button.innerHTML=`<span class="slot-number">${String(index+1).padStart(2,'0')}</span><canvas width="300" height="192" aria-hidden="true"></canvas>${index===0?`<span class="status-mark ${enemy?'fire':''}">${enemy?'灼 2':'御'}</span>`:''}<span class="piece-info"><span>${names[kind]}</span><span class="piece-hp">${hp[0]} <span style="opacity:.5">/ ${hp[1]}</span></span></span><span class="hp-track"><i style="width:${hp[0]/hp[1]*100}%"></i></span>`;
      root.append(button);
      const ctx=button.querySelector('canvas').getContext('2d');ctx.scale(2,2);
      window.BattleConceptPieces.drawPiece(ctx,kind,75,88,.48,enemy?-1:1,enemy,0);
      button.onclick=()=>onPiece(button);
    });
  }
  buildArmy(false);buildArmy(true);
  function renderHand(){
    const hand=$('#hand');hand.classList.toggle('seven',seven);hand.replaceChildren();
    cards.forEach((card,index)=>{
      const button=document.createElement('button');button.className='card';button.dataset.id=card.id;button.dataset.icon=card.icon;
      const offset=index-(cards.length-1)/2;
      button.style.setProperty('--tilt',(offset*(seven?1.3:1.7))+'deg');button.style.setProperty('--lift',(Math.abs(offset)*3)+'px');
      button.classList.toggle('selected',card.id===selected);button.classList.toggle('unaffordable',card.cost>sp);
      button.setAttribute('aria-pressed',String(card.id===selected));button.setAttribute('aria-label',`${card.name}，费用 ${card.cost}。${card.full}`);
      button.title=card.full;
      button.innerHTML=`<span class="card-cost">${card.cost}</span><span class="card-category">自由技</span><span class="card-art"><svg viewBox="0 0 100 84" aria-hidden="true">${icons[card.icon]}</svg></span><span class="card-title">${card.name}</span><span class="card-desc">${card.description}</span><span class="card-bottom"><span>公共</span><span>使用后弃置</span></span>`;
      button.onclick=()=>selectCard(card);
      hand.append(button);
    });
    $('#hand-count').textContent=['零','壹','贰','叁','肆','伍','陆','柒'][cards.length];
    $('#sp').textContent=sp;$('#sp-total').textContent=sp;$('#discard-count').textContent=discarded;
    $('.sp-arc').style.strokeDasharray=`${sp/10*270} 271`;
  }
  function setHint(text){$('#hint').textContent=text;}
  function clearSelection(){selected=null;document.querySelectorAll('.piece').forEach(p=>p.classList.remove('valid','inspect'));document.querySelectorAll('.card').forEach(c=>{c.classList.remove('selected');c.setAttribute('aria-pressed','false')});setHint('◇  以牌为令，落子成势。  选择手牌，查看作用目标');}
  function selectCard(card){
    if(busy)return;
    if(sp<card.cost){toast('技能点不足，结束回合可重置演示手牌。');return;}
    if(selected===card.id){clearSelection();return;}
    clearTimeout(selectionTimer);clearSelection();selected=card.id;
    const el=document.querySelector(`.card[data-id="${card.id}"]`);el.classList.add('selected');el.setAttribute('aria-pressed','true');
    document.querySelectorAll('.piece').forEach(p=>{
      const valid=(card.target==='ally'||card.target==='single')?p.dataset.side==='ally':p.dataset.side==='enemy'&&Number(p.dataset.index)===(card.target==='burn'?0:3);
      p.classList.toggle('valid',valid);
    });
    setHint(`${card.name} · ${card.target==='ally'?'作用于全体我方棋子':card.target==='single'?'选择一枚我方棋子':'已标出规则对应的示例目标'}，点击亮起的棋子预览施放`);
  }
  function onPiece(piece){
    if(busy)return;
    if(selected===null){
      document.querySelectorAll('.piece').forEach(p=>p.classList.remove('inspect'));piece.classList.add('inspect');
      setHint(piece.getAttribute('aria-label')+' · 选择手牌以预览施放');return;
    }
    if(!piece.classList.contains('valid')){toast('请选择亮起的作用目标。');return;}
    const card=cards.find(c=>c.id===selected);
    const targets=card.target==='ally'?[...document.querySelectorAll('#allies .piece')]:[piece];
    targets.forEach(t=>{t.classList.remove('pulse');void t.offsetWidth;t.classList.add('pulse');});
    const flash=$('#board-flash');flash.classList.remove('flash');void flash.offsetWidth;flash.classList.add('flash');
    sp-=card.cost;discarded++;cards=cards.filter(c=>c.id!==card.id);
    logs.unshift(`演示施放「${card.name}」，消耗 ${card.cost} SP。${card.effect}。`);
    clearSelection();renderHand();setHint('◇ '+card.effect+' · 施放效果预览');toast(card.effect);
    selectionTimer=setTimeout(()=>{if(selected===null&&!busy)setHint('◇  以牌为令，落子成势。  选择手牌，查看作用目标');},2200);
  }
  function toast(text){clearTimeout(toastTimer);$('#toast').textContent=text;$('#toast').classList.add('show');toastTimer=setTimeout(()=>$('#toast').classList.remove('show'),2200);}
  function showDialog(title,content){$('#dialog-title').textContent=title;$('#dialog-content').innerHTML=content;$('#detail-dialog').showModal();}
  $('#dialog-close').onclick=()=>$('#detail-dialog').close();
  const rosterData=[
    {id:'knight',name:'骑士',role:'守护',skill:'反击',kind:'被动专属',energy:65,image:'qishi_lihui_transparent.png',detail:'上阵时，我方棋子获得格挡增益；格挡成功时触发反击。这是被动专属，不生成主动专属卡。'},
    {id:'chiyan',name:'赤焰',role:'灼烧',skill:'蔓炎',kind:'主动专属',energy:85,image:'chiyan_lihui_transparent_v2.png',detail:'使已有灼烧层数翻倍，并延长 2 回合。第 1 / 2 / 3 / 4 次释放消耗 1 / 2 / 4 / 8 技能点。主动专属通过手牌使用。'},
    {id:'chenge',name:'辰歌',role:'破势',skill:'破势',kind:'主动专属',energy:35,image:'chenge_lihui_transparent.png',detail:'消耗 1 技能点，对单体造成直接伤害并施加破势，优先攻击未被破势的目标。主动专属通过手牌使用。'}
  ];
  const heroRoster=document.createElement('aside');heroRoster.className='hero-roster';heroRoster.hidden=true;heroRoster.setAttribute('aria-label','我方三位弈者');
  heroRoster.innerHTML='<div class="side-label"><span></span>我方弈者 · 叁<span></span></div><div class="roster-list"></div><p class="hero-roster-note">各自蓄势，共执一局</p>';
  scene.append(heroRoster);
  rosterData.forEach(hero=>{
    const button=document.createElement('button');button.className='mini-hero';button.dataset.hero=hero.id;
    button.setAttribute('aria-label',`${hero.name}，能量 ${hero.energy}/100，${hero.kind}：${hero.skill}。点击查看说明。`);
    button.innerHTML=`<span class="mini-portrait"><img src="../../assets/portraits/${hero.image}" alt="${hero.name}立绘" draggable="false"></span><span class="mini-identity"><span class="mini-role">${hero.role}</span><span class="mini-name">${hero.name}</span><span class="mini-skill">${hero.skill}</span><span class="mini-skill-kind">${hero.kind}</span></span><span class="mini-energy"><span>能量</span><span><b>${hero.energy}</b><small> / 100</small></span></span><span class="mini-energy-track"><i style="width:${hero.energy}%"></i></span><span class="mini-detail" aria-hidden="true"><strong>${hero.name} · ${hero.skill}</strong>${hero.detail}<small>能量满时清零并生成大招卡。满手时，大招卡进入抽牌堆顶。</small></span>`;
    button.onclick=()=>{button.classList.add('dismissed');showDialog(`${hero.name} · ${hero.skill}`,`<p class="detail-text">${hero.detail}</p><p class="detail-text">当前示例能量：<strong>${hero.energy} / 100</strong>。<br>能量满时清零并生成大招卡；满手时放入抽牌堆顶。</p>`);};
    button.onmouseenter=button.onfocus=()=>button.classList.remove('dismissed');
    heroRoster.querySelector('.roster-list').append(button);
  });
  let threeHeroes=new URLSearchParams(location.search).get('heroes')==='3';
  function setHeroMode(){scene.classList.toggle('three-heroes',threeHeroes);heroRoster.hidden=!threeHeroes;$('.hero-ally').hidden=threeHeroes;$('#heroes-toggle').setAttribute('aria-pressed',String(threeHeroes));$('#heroes-toggle').textContent=threeHeroes?'单弈者':'三弈者';}
  $('#heroes-toggle').onclick=()=>{threeHeroes=!threeHeroes;setHeroMode();};
  setHeroMode();
  $('#detail-dialog').addEventListener('click',e=>{if(e.target===$('#detail-dialog')){const r=e.target.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)e.target.close();}});
  $('#log-open').onclick=()=>showDialog('棋局战报',logs.map((l,i)=>`<div class="log-row"><b>${String(logs.length-i).padStart(2,'0')}</b>${l}</div>`).join(''));
  $('#draw-open').onclick=()=>showDialog('抽牌堆 · 示例',initialCards.map(c=>`<div class="detail-row"><span>${c.name}</span><small>${c.cost} SP · 自由技</small></div>`).join('')+'<p class="detail-text">牌堆标示 9 张，此处展示其中的 5 种卡牌样式。</p>');
  $('#discard-open').onclick=()=>showDialog('弃牌堆 · 示例',`<p class="detail-text">当前弃牌 <strong>${discarded}</strong> 张。<br>点击手牌并对亮起的目标施放，可观察卡牌离手、技能点扣除和弃牌计数的反馈。</p>`);
  function setBusy(value){busy=value;scene.classList.toggle('busy',value);$('#end-turn').disabled=value;$('#hand-toggle').disabled=value;}
  $('#end-turn').onclick=()=>{
    if(busy)return;clearTimeout(selectionTimer);clearSelection();setBusy(true);$('#phase').textContent='敌方行动';setHint('◇  敌阵出手 · 回合过渡演示');$('#end-turn span').textContent='敌方行动';
    document.querySelectorAll('#enemies .piece').forEach(p=>{p.classList.remove('pulse');void p.offsetWidth;p.classList.add('pulse');});
    turnTimer=setTimeout(()=>{round++;sp=10;selected=null;makeCards();renderHand();$('#round-number').textContent=round;$('#phase').textContent='我方行动';$('#end-turn span').textContent='结束回合';setBusy(false);logs.unshift(`第 ${round} 回合演示开始，重置样例手牌与技能点。`);setHint('◇  新的回合 · 样例手牌与技能点已重置');toast('我方回合');},matchMedia('(prefers-reduced-motion: reduce)').matches?80:1200/speed);
  };
  $('#hand-toggle').onclick=()=>{if(busy)return;clearTimeout(selectionTimer);seven=!seven;selected=null;clearSelection();makeCards();renderHand();$('#hand-toggle').setAttribute('aria-pressed',String(seven));$('#hand-toggle').textContent=seven?'五张手牌':'满手预览';toast(seven?'七张满手 · 悬停可抬起阅牌':'五张手牌 · 舒展布局');};
  document.querySelectorAll('[data-speed]').forEach(b=>b.onclick=()=>{speed=Number(b.dataset.speed);document.querySelectorAll('[data-speed]').forEach(x=>{const active=x===b;x.classList.toggle('active',active);x.setAttribute('aria-pressed',String(active));});toast(`回合过渡速度 ${speed}×`);});
  $('#reset').onclick=()=>{clearTimeout(turnTimer);clearTimeout(selectionTimer);setBusy(false);sp=7;discarded=4;round=3;seven=false;selected=null;logs.splice(0,logs.length,'第三回合开始。当前为美术概念示例状态。');makeCards();clearSelection();renderHand();$('#round-number').textContent='三';$('#phase').textContent='我方行动';$('#end-turn span').textContent='结束回合';$('#hand-toggle').textContent='满手预览';$('#hand-toggle').setAttribute('aria-pressed','false');toast('已回到初始画面');};
  addEventListener('keydown',e=>{if(e.key==='Escape'){document.querySelectorAll('.mini-hero').forEach(b=>b.classList.add('dismissed'));if(!$('#detail-dialog').open)clearSelection();}});
  makeCards();renderHand();
})();
