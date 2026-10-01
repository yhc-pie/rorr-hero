import os
CSS=open('/tmp/vizsrc/common.css').read()
HEAD='''<!doctype html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport" content="width=960, height=540"/>
<link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@600;700&family=JetBrains+Mono:wght@500;700&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
<style>'''+CSS+'''__CSS__</style></head><body>
<div id="stage" data-composition-id="__CID__" data-start="0" data-duration="6" data-fps="30" data-width="960" data-height="540">
<div id="main" class="clip" data-start="0" data-duration="6" data-track-index="0" style="width:100%;height:100%">
__BODY__
</div></div>
<script>
const tl=gsap.timeline({paused:true});
__JS__
window.__timelines=window.__timelines||{};window.__timelines["__CID__"]=tl;tl.seek(0);
</script></body></html>'''
V={}
# ---------- 1. DRAKE: countdown ring + win chance split ----------
V['drake']=('''
.wrap{display:flex;align-items:center;gap:64px;height:100%}
.ring{position:relative;width:300px;height:300px;flex:none}
.ring svg{position:absolute;inset:0}
.ring .c{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px}
.ring .t{font-size:72px;color:var(--ink)}
.ring .l{font-size:22px;letter-spacing:.2em;color:var(--gold)}
.right{flex:1;display:flex;flex-direction:column;gap:26px}
.teams{display:flex;justify-content:space-between;font-size:26px;letter-spacing:.08em}
.teams .a{color:var(--cyan)}.teams .b{color:var(--mute)}
.bar{height:22px;border-radius:999px;background:var(--line);overflow:hidden;display:flex}
.bar i{display:block;height:100%;background:var(--cyan)}
.pcts{display:flex;justify-content:space-between;align-items:baseline}
.pcts .p{font-size:64px}.pcts .p.a{color:var(--cyan)}.pcts .p.b{color:var(--mute);font-size:40px}
.delta{font-size:24px;color:var(--gold);letter-spacing:.06em}
''','drake','''<div class="scene-content"><div class="wrap">
 <div class="ring"><svg viewBox="0 0 300 300"><circle cx="150" cy="150" r="130" fill="none" stroke="#262836" stroke-width="14"/>
  <circle id="arc" cx="150" cy="150" r="130" fill="none" stroke="#FFC24A" stroke-width="14" stroke-linecap="round" transform="rotate(-90 150 150)" stroke-dasharray="816.8" stroke-dashoffset="0"/></svg>
  <div class="c"><div class="t big" id="cd">0:40</div><div class="l">DRAKE</div></div></div>
 <div class="right">
  <div class="tag" id="tg">WIN CHANCE · <b>24:10</b></div>
  <div class="teams" id="tm"><span class="a">T1</span><span class="b">GEN</span></div>
  <div class="bar" id="br"><i id="fill" style="width:52%"></i></div>
  <div class="pcts" id="pc"><span class="p a big" id="pa">52%</span><span class="p b big" id="pb">48%</span></div>
  <div class="delta" id="dl">▲ +6 IF T1 TAKES DRAKE</div>
 </div></div></div>''','''
const C=816.8;
tl.fromTo(".ring",{autoAlpha:0,scale:.86},{autoAlpha:1,scale:1,duration:.6,ease:"back.out(1.6)"},0);
tl.fromTo(["#tg","#tm","#br","#pc"],{autoAlpha:0,y:18},{autoAlpha:1,y:0,duration:.5,stagger:.12,ease:"power3.out"},.25);
const cd={v:40};tl.fromTo(cd,{v:40},{v:34,duration:4.6,ease:"none",onUpdate:()=>{document.getElementById("cd").textContent="0:"+String(Math.ceil(cd.v)).padStart(2,"0")}},.4);
tl.fromTo("#arc",{attr:{"stroke-dashoffset":0}},{attr:{"stroke-dashoffset":C*(6/40)},duration:4.6,ease:"none"},.4);
const w={v:52};tl.fromTo(w,{v:52},{v:58,duration:1.4,ease:"power2.inOut",onUpdate:()=>{const v=Math.round(w.v);document.getElementById("fill").style.width=w.v+"%";document.getElementById("pa").textContent=v+"%";document.getElementById("pb").textContent=(100-v)+"%"}},1.6);
tl.fromTo("#dl",{autoAlpha:0,x:-12},{autoAlpha:1,x:0,duration:.5,ease:"power3.out"},2.9);
tl.to("#stage",{duration:6-tl.duration()},tl.duration());
''')
# ---------- 2. FLASH: summoner spell board ----------
rows=['TOP','JG','MID','BOT','SUP']
def col(team,cls,down):
    s=f'<div class="col"><div class="th {cls}">{team}</div>'
    for r in rows:
        d=r in down
        s+=f'<div class="row"><span class="role">{r}</span><span class="f{" down" if d else ""}" id="{team}-{r}"><svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="16" fill="none" stroke="currentColor" stroke-width="3"/><path d="M22 8 L13 22 H20 L18 32 L27 18 H20 Z" fill="currentColor"/></svg>{"<em>"+("4:12" if r=="BOT" else "3:58")+"</em>" if d else ""}</span></div>'
    return s+'</div>'
V['flash']=('''
.board{display:grid;grid-template-columns:1fr 220px 1fr;align-items:center;height:100%;gap:24px}
.col{display:flex;flex-direction:column;gap:12px}
.th{font-size:28px;letter-spacing:.1em;margin-bottom:6px}.th.a{color:var(--cyan)}.th.b{color:var(--mute)}
.row{display:flex;align-items:center;justify-content:space-between;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:8px 16px;height:58px}
.role{font-size:22px;color:var(--mute);letter-spacing:.06em}
.f{display:flex;align-items:center;gap:10px;color:var(--gold);font-size:22px}.f svg{width:30px;height:30px}
.f em{font-style:normal;color:var(--mute)}
.mid{display:flex;flex-direction:column;align-items:center;gap:10px}
.score{font-size:76px;letter-spacing:.02em}.score .a{color:var(--cyan)}.score .s{color:#6E7080;margin:0 10px}.score .b{color:var(--mute)}
.mid .l{font-size:22px;letter-spacing:.16em;color:var(--gold)}
.mid .t{font-size:22px;letter-spacing:.1em;color:var(--mute)}
''','flash','<div class="scene-content"><div class="board">'+col('T1','a',[])+'<div class="mid"><div class="t" id="tt">21:42</div><div class="score big" id="sc"><span class="a" id="ka">0</span><span class="s">–</span><span class="b">0</span></div><div class="l" id="fl">FIGHT</div></div>'+col('GEN','b',['BOT','SUP'])+'</div></div>','''
tl.fromTo(".col .th",{autoAlpha:0,y:12},{autoAlpha:1,y:0,duration:.4,stagger:.1,ease:"power3.out"},0);
tl.fromTo(".row",{autoAlpha:0,y:14},{autoAlpha:1,y:0,duration:.4,stagger:.05,ease:"power3.out"},.15);
tl.fromTo(["#GEN-BOT","#GEN-SUP"],{color:"#FFC24A"},{color:"#4A4C5C",duration:.4,stagger:.15,ease:"power1.out"},1.3);
tl.fromTo(["#GEN-BOT em","#GEN-SUP em"],{autoAlpha:0,x:-8},{autoAlpha:1,x:0,duration:.35,stagger:.15},1.4);
tl.fromTo(["#GEN-BOT","#GEN-SUP"].map(s=>s),{scale:1},{scale:1.12,duration:.18,yoyo:true,repeat:1,stagger:.15,ease:"power2.out"},1.3);
tl.fromTo(["#tt","#sc"],{autoAlpha:0,scale:.9},{autoAlpha:1,scale:1,duration:.45,stagger:.08,ease:"back.out(1.7)"},2.2);
const k={v:0};tl.fromTo(k,{v:0},{v:3,duration:1.1,ease:"steps(3)",onUpdate:()=>{document.getElementById("ka").textContent=Math.round(k.v)}},2.8);
tl.fromTo("#fl",{autoAlpha:0,y:8},{autoAlpha:1,y:0,duration:.4,ease:"power3.out"},2.6);
tl.to("#stage",{duration:6-tl.duration()},tl.duration());
''')
# ---------- 3. GOLD: lead breakdown ----------
data=[('JG',1450),('MID',700),('BOT',600),('TOP',300),('SUP',150)]
bars=''.join(f'<div class="r"><span class="role">{r}</span><div class="track"><i id="b{i}" style="width:{v/1450*100:.1f}%"></i></div><span class="v" id="v{i}">+{v:,}</span></div>' for i,(r,v) in enumerate(data))
V['gold']=('''
.head{display:flex;align-items:baseline;justify-content:space-between}
.total{font-size:84px;color:var(--ink)}.total small{font-size:22px;color:var(--mute);margin-left:12px;letter-spacing:.1em;font-family:"JetBrains Mono"}
.list{display:flex;flex-direction:column;gap:14px}
.r{display:grid;grid-template-columns:80px 1fr 130px;align-items:center;gap:18px}
.role{font-size:24px;color:var(--mute);letter-spacing:.06em}
.track{height:28px;border-radius:8px;background:var(--line);overflow:hidden}
.track i{display:block;height:100%;border-radius:8px;background:var(--dim)}
#b0{background:var(--gold)}
.v{font-size:26px;text-align:right;color:var(--mute)}#v0{color:var(--gold)}
''','gold','<div class="scene-content"><div class="tag" id="tg">GOLD LEAD · <b>T1</b> · wGE+ BY ROLE</div><div class="head"><div class="total big" id="tot">+0<small>GOLD</small></div></div><div class="list">'+bars+'</div></div>','''
const D=%s;
tl.fromTo("#tg",{autoAlpha:0,y:10},{autoAlpha:1,y:0,duration:.4,ease:"power3.out"},0);
tl.fromTo("#tot",{autoAlpha:0,y:16},{autoAlpha:1,y:0,duration:.5,ease:"power3.out"},.15);
const t={v:0};tl.fromTo(t,{v:0},{v:3200,duration:1.6,ease:"power2.out",onUpdate:()=>{document.getElementById("tot").firstChild.nodeValue="+"+Math.round(t.v).toLocaleString("en-US")}},.3);
tl.fromTo(".r",{autoAlpha:0,x:-14},{autoAlpha:1,x:0,duration:.35,stagger:.08,ease:"power3.out"},.6);
D.forEach((v,i)=>{tl.fromTo("#b"+i,{width:"0%%"},{width:(v/1450*100)+"%%",duration:1.1,ease:"power3.out"},.8+i*.12)});
tl.fromTo("#b0",{boxShadow:"0 0 0 rgba(255,194,74,0)"},{boxShadow:"0 0 24px rgba(255,194,74,.55)",duration:.5,yoyo:true,repeat:1,ease:"sine.inOut"},2.6);
tl.to("#stage",{duration:6-tl.duration()},tl.duration());
'''%str([v for _,v in data]))
# ---------- 4. COMEBACK: win chance line ----------
# points: (minute, pct)
pts=[(0,50),(4,52),(8,49),(12,45),(15,44),(18,42),(20,41),(21.7,43),(23,49),(24.2,52),(24.6,58),(25.3,60),(26.1,63)]
W,H=760,300;X0,Y0=60,40
def xy(m,p):return (X0+m/26.1*(W-X0-20), Y0+(1-(p-30)/40)*(H-Y0-30))
path='M'+' L'.join(f'{x:.1f} {y:.1f}' for x,y in (xy(m,p) for m,p in pts))
x50=xy(0,50)[1];dx,dy=xy(24.2,52);bx,by=xy(25.3,60);ex,ey=xy(26.1,63);lx,ly=xy(20,41)
V['comeback']=('''
.chart{position:relative}
.chart svg{display:block}
.lbl{font-family:"JetBrains Mono";font-size:20px;fill:#8C8C9A;letter-spacing:.08em}
.end{font-family:"Chakra Petch";font-weight:700;font-size:44px;fill:#FFC24A}
.low{font-family:"Chakra Petch";font-weight:700;font-size:26px;fill:#8C8C9A}
.obj{font-family:"JetBrains Mono";font-size:19px;fill:#35F0DC;letter-spacing:.12em}
''','comeback',f'''<div class="scene-content"><div class="tag" id="tg">WIN CHANCE · <b>T1</b> · 0:00 → 26:05</div><div class="chart">
<svg width="{W+120}" height="{H}" viewBox="0 0 {W+120} {H}">
 <line x1="{X0}" y1="{x50:.1f}" x2="{W-20}" y2="{x50:.1f}" stroke="#262836" stroke-width="2" stroke-dasharray="6 8"/>
 <text class="lbl" x="0" y="{x50+5:.1f}">50%</text>
 <line id="axis" x1="{X0}" y1="{H-30}" x2="{W-20}" y2="{H-30}" stroke="#262836" stroke-width="2"/>
 <text class="lbl" x="{X0}" y="{H-6}">0:00</text><text class="lbl" x="{W-80}" y="{H-6}">26:05</text>
 <path id="ln" d="{path}" fill="none" stroke="#35F0DC" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
 <g id="lowp"><circle cx="{lx:.1f}" cy="{ly:.1f}" r="7" fill="#8C8C9A"/><text class="low" x="{lx-30:.1f}" y="{ly+40:.1f}">41%</text></g>
 <g id="o1"><circle cx="{dx:.1f}" cy="{dy:.1f}" r="8" fill="#0E0F15" stroke="#35F0DC" stroke-width="3"/><text class="obj" x="{dx-150:.1f}" y="{dy+6:.1f}">DRAGON</text></g>
 <g id="o2"><circle cx="{bx:.1f}" cy="{by:.1f}" r="8" fill="#0E0F15" stroke="#35F0DC" stroke-width="3"/><text class="obj" x="{bx-120:.1f}" y="{by-14:.1f}">BARON</text></g>
 <g id="endp"><circle cx="{ex:.1f}" cy="{ey:.1f}" r="10" fill="#FFC24A"/><text class="end" x="{ex+18:.1f}" y="{ey+14:.1f}">63%</text></g>
</svg></div></div>''','''
const ln=document.getElementById("ln");const L=ln.getTotalLength();ln.style.strokeDasharray=L;
tl.fromTo("#tg",{autoAlpha:0,y:10},{autoAlpha:1,y:0,duration:.4,ease:"power3.out"},0);
tl.fromTo("#ln",{strokeDashoffset:L},{strokeDashoffset:0,duration:3.2,ease:"power1.inOut"},.3);
tl.fromTo("#lowp",{autoAlpha:0,scale:.6,transformOrigin:"50% 50%"},{autoAlpha:1,scale:1,duration:.4,ease:"back.out(2)"},1.9);
tl.fromTo("#o1",{autoAlpha:0},{autoAlpha:1,duration:.35},2.85);
tl.fromTo("#o2",{autoAlpha:0},{autoAlpha:1,duration:.35},3.25);
tl.fromTo("#endp",{autoAlpha:0,scale:.5,transformOrigin:"50% 50%"},{autoAlpha:1,scale:1,duration:.5,ease:"back.out(2.2)"},3.5);
tl.to("#stage",{duration:6-tl.duration()},tl.duration());
''')
for k,(css,cid,body,js) in V.items():
    open(f'/home/claude/videos/viz-{k}/index.html','w').write(HEAD.replace('__CSS__',css).replace('__BODY__',body).replace('__JS__',js).replace('__CID__',cid))
print('ok')
