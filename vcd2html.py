#!/usr/bin/env python3
"""
VCD → HTML waveform viewer (no X11 needed, opens in Chrome/Firefox)
BLM2022 Odev 3 - Omar Nuriyev 24011902
"""
import re, sys, os

VCD_FILE = "24011902.vcd"
HTML_OUT = "24011902_wave.html"

# --- Parse VCD ---
def parse_vcd(path):
    ids   = {}   # symbol -> (name, width)
    vals  = {}   # symbol -> current int value
    times = []   # (timestamp, {sym: val, ...})
    cur_t = 0
    cur_changes = {}

    with open(path) as f:
        in_header = True
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Variable declarations
            m = re.match(r'\$var\s+\S+\s+(\d+)\s+(\S+)\s+(\S+)', line)
            if m:
                width, sym, name = int(m.group(1)), m.group(2), m.group(3)
                if sym not in ids:
                    ids[sym] = (name, width)
                    vals[sym] = 0
                continue

            if '$end' in line and in_header:
                if 'enddefinitions' in line:
                    in_header = False
                continue

            # Timestamp
            if line.startswith('#'):
                if cur_changes:
                    times.append((cur_t, dict(cur_changes)))
                    cur_changes = {}
                cur_t = int(line[1:])
                continue

            # Value changes
            # scalar:  0" or 1" or x"
            m = re.match(r'^([01xzXZ])(.+)$', line)
            if m:
                v_str, sym = m.group(1), m.group(2)
                v = 0 if v_str in ('0','x','X','z','Z') else 1
                cur_changes[sym] = v
                vals[sym] = v
                continue

            # vector:  b00101010 #
            m = re.match(r'^b([01xzXZ]+)\s+(.+)$', line)
            if m:
                b_str, sym = m.group(1), m.group(2)
                try:
                    v = int(b_str.replace('x','0').replace('z','0'), 2)
                except:
                    v = 0
                cur_changes[sym] = v
                vals[sym] = v
                continue

        if cur_changes:
            times.append((cur_t, dict(cur_changes)))

    return ids, times

print("Parsing VCD…")
ids, times = parse_vcd(VCD_FILE)

# Find symbol IDs for our signals
# From header: ! = WriteData, " = MemWrite, # = DataAdr, $ = clk, % = reset
target = {"clk": "$", "reset": "%", "MemWrite": '"', "DataAdr": "#", "WriteData": "!"}

# Reconstruct signal timelines
def build_timeline(times, sym):
    tl = []   # [(time, value), ...]
    cur = 0
    for t, changes in times:
        if sym in changes:
            cur = changes[sym]
            tl.append((t, cur))
    return tl

print("Building timelines…")
tl = {name: build_timeline(times, sym) for name, sym in target.items()}

# Find MemWrite pulses → extract SW events
mw_events = []  # [(time_ps, addr, data)]
last_mw = 0
last_addr = 0
last_data = 0

# merge all signals by time
all_times = sorted(set(t for t, _ in times))

# Rebuild state machine
state = {"clk":0,"reset":1,"MemWrite":0,"DataAdr":0,"WriteData":0}
sw_events = []
prev_clk = 0

for t, changes in times:
    state.update({k: v for k, sym in target.items()
                  for c_sym, cv in changes.items() if c_sym == sym
                  for k, v in [(k, cv)]})
    # detect posedge clk
    if '"' in changes and changes['"']:  # MemWrite goes high
        last_mw_t = t
    for name, sym in target.items():
        if sym in changes:
            state[name] = changes[sym]
    if '"' in changes:
        mw = changes['"']
        if mw == 1:
            mw_events.append((t, state["DataAdr"], state["WriteData"]))

# Filter to COUNT array writes (addr 84-160 = 0x54-0xA0)
count_writes = [(t, addr, data) for t, addr, data in mw_events
                if 84 <= addr <= 160]

print(f"Found {len(count_writes)} COUNT writes")

# Timescale is 1ps, clock period = 10ns = 10000ps
# Cycle N starts at posedge N → time ≈ (25000 + (N-1)*10000) ps
# (reset deasserts at 22000ps, first posedge at 25000ps)

max_t = times[-1][0] if times else 1
clk_data  = tl["clk"]
mw_data   = tl["MemWrite"]
addr_data = tl["DataAdr"]
data_data = tl["WriteData"]

def compress(tl_in, max_t):
    """Convert timeline to JS array [[t_ns, val], ...]"""
    out = []
    for t, v in tl_in:
        out.append([round(t/1000, 1), v])
    out.append([round(max_t/1000, 1), out[-1][1] if out else 0])
    return out

clk_js  = compress(clk_data,  max_t)
mw_js   = compress(mw_data,   max_t)
addr_js = compress(addr_data, max_t)
data_js = compress(data_data, max_t)

# Count write annotations
annots = []
for i, (t, addr, data) in enumerate(count_writes):
    idx = (addr - 84) // 4
    annots.append({"t": round(t/1000,1), "addr": addr, "data": data, "idx": idx})

# Special highlights
specials = [
    {"label": "0xFFFFFFFF", "count": 16, "idx": 9},
    {"label": "0x80000000", "count": 0,  "idx": 4},
    {"label": "0xC7B52169", "count": 9,  "idx": 12},
]
for s in specials:
    if s["idx"] < len(annots):
        s["t"] = annots[s["idx"]]["t"]
        s["cycle"] = 111 + s["idx"] * 109

HTML = f"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>24011902 - GTKWave (VCD Viewer)</title>
<style>
  body {{ font-family: monospace; background:#1e1e1e; color:#d4d4d4; margin:0; padding:10px; }}
  h2   {{ color:#4ec9b0; margin:4px 0; font-size:14px; }}
  h3   {{ color:#9cdcfe; margin:8px 0 4px; font-size:13px; }}
  canvas {{ display:block; border:1px solid #444; background:#111; }}
  .panel  {{ background:#252526; border:1px solid #444; border-radius:4px;
             padding:8px; margin-bottom:10px; }}
  .ctrl   {{ display:flex; gap:8px; flex-wrap:wrap; margin-bottom:6px; align-items:center; }}
  button  {{ background:#0e639c; color:#fff; border:none; border-radius:3px;
             padding:4px 10px; cursor:pointer; font-size:12px; }}
  button:hover {{ background:#1177bb; }}
  .hl-btn {{ background:#6a4e20; }}
  .hl-btn:hover {{ background:#8a6e30; }}
  .info   {{ font-size:11px; color:#888; margin-top:4px; }}
  table   {{ border-collapse:collapse; width:100%; font-size:12px; }}
  td,th   {{ border:1px solid #555; padding:3px 6px; }}
  th      {{ background:#333; color:#4ec9b0; }}
  tr:nth-child(even) {{ background:#2a2a2a; }}
  .pass   {{ color:#4ec9b0; }} .fail {{ color:#f44; }}
  .spec   {{ background:#2d2a1a !important; }}
</style>
</head>
<body>

<div class="panel">
  <h2>BLM2022 Ödev 3 — Dalga Formu | 24011902 Omar Nuriyev</h2>
  <div class="info">Sinyaller: clk · MemWrite · DataAdr · WriteData &nbsp;|&nbsp; Timescale: 1ns &nbsp;|&nbsp; Toplam: {round(max_t/1000,0):.0f} ns</div>
</div>

<div class="panel">
  <h3>Dalga Formu</h3>
  <div class="ctrl">
    <button onclick="zoom(2)">Zoom +</button>
    <button onclick="zoom(0.5)">Zoom −</button>
    <button onclick="zoomFit()">Fit</button>
    <button onclick="scroll(-200)">◀</button>
    <button onclick="scroll(200)">▶</button>
    <span style="font-size:11px;color:#888">Cursor: <span id="cur_t">—</span> ns</span>
  </div>
  <canvas id="wave" width="900" height="280"></canvas>
  <div class="info">
    Özel değerler:
    {"  |  ".join(f'<span style="color:#ffa500">{s["label"]}</span> → COUNT={s["count"]} @ t={s.get("t","?")} ns (cevrim {s.get("cycle","?")})'
                  for s in specials)}
  </div>
  <div class="ctrl" style="margin-top:6px">
    {'  '.join(f'<button class="hl-btn" onclick="goTo({s.get("t",0)})">{s["label"]} (cevrim {s.get("cycle","?")})</button>'
               for s in specials)}
  </div>
</div>

<div class="panel">
  <h3>COUNT Dizisi — Sonuçlar</h3>
  <table>
    <tr><th>Sıra</th><th>ARRAY</th><th>Beklenen</th><th>Simülasyon</th><th>Cevrim</th><th>Durum</th></tr>
    {"".join(
      f'<tr class="{"spec" if annots[i]["idx"] in [4,9,12] else ""}"><td>{i+1}</td>'
      f'<td>0x{["00000000","00000001","00000200","00400000","80000000","51C06460","DEC287D9","6C896594","99999999","FFFFFFFF","7FFFFFFF","FFFFFFFE","C7B52169","8CEFF731","A550921E","0DB01F33","24BB7B48","98513914","CD76ED30","C0000003"][i]}</td>'
      f'<td>{[0,1,0,1,0,7,9,8,8,16,16,15,9,10,7,8,7,8,10,2][i]}</td>'
      f'<td>{annots[i]["data"] if i < len(annots) else "—"}</td>'
      f'<td>{111+i*109}</td>'
      f'<td class="{"pass" if i < len(annots) and annots[i]["data"]==[0,1,0,1,0,7,9,8,8,16,16,15,9,10,7,8,7,8,10,2][i] else "fail"}">{"✓ PASS" if i < len(annots) and annots[i]["data"]==[0,1,0,1,0,7,9,8,8,16,16,15,9,10,7,8,7,8,10,2][i] else "✗ FAIL"}</td></tr>'
      for i in range(min(20, len(annots)))
    )}
  </table>
  <div class="info" style="margin-top:6px">Her eleman: 109 cevrim (sabit) | Toplam: 2187 cevrim | Son COUNT: cevrim 2182</div>
</div>

<script>
const CLK  = {clk_js};
const MW   = {mw_js};
const ADDR = {addr_js};
const DATA = {data_js};
const ANNOTS = {annots};
const SPECIALS = {specials};

const MAX_T = {round(max_t/1000,1)};

let viewStart = 0;
let viewEnd   = MAX_T;
let dragging    = false;
let dragX0      = 0;
let dragV0Start = 0;
let dragV0Span  = 0;

const C = document.getElementById('wave');
const ctx = C.getContext('2d');

function resize() {{
  C.width = Math.min(window.innerWidth - 40, 1400);
  draw();
}}

function zoom(factor) {{
  const mid = (viewStart + viewEnd) / 2;
  const half = (viewEnd - viewStart) / 2 * factor;
  viewStart = Math.max(0, mid - half);
  viewEnd   = Math.min(MAX_T, mid + half);
  draw();
}}

function zoomFit() {{ viewStart=0; viewEnd=MAX_T; draw(); }}

function scroll(px) {{
  const dt = (viewEnd - viewStart) * px / C.width;
  viewStart = Math.max(0, viewStart + dt);
  viewEnd   = Math.min(MAX_T, viewEnd + dt);
  draw();
}}

function goTo(t) {{
  const span = (viewEnd - viewStart);
  viewStart = Math.max(0, t - span*0.3);
  viewEnd   = viewStart + span;
  if (viewEnd > MAX_T) {{ viewEnd = MAX_T; viewStart = Math.max(0, viewEnd - span); }}
  draw();
}}

function tToX(t) {{
  return (t - viewStart) / (viewEnd - viewStart) * C.width;
}}

function getVal(tl, t) {{
  let v = tl[0][1];
  for (const [pt, pv] of tl) {{ if (pt <= t) v = pv; else break; }}
  return v;
}}

function drawSignal(tl, y, h, label, color, isBus) {{
  const W = C.width;
  ctx.strokeStyle = color;
  ctx.lineWidth = 1.5;
  ctx.fillStyle = color + '33';
  ctx.font = '11px monospace';
  ctx.fillStyle = '#aaa';
  ctx.fillText(label, 2, y + h/2 + 4);

  const SIG_X = 90;
  ctx.save();
  ctx.beginPath();
  ctx.rect(SIG_X, 0, W - SIG_X, C.height);
  ctx.clip();

  if (!isBus) {{
    // Digital: 0 or 1
    ctx.strokeStyle = color;
    ctx.beginPath();
    let first = true;
    let pv = null, px = SIG_X;
    for (const [t, v] of tl) {{
      const x = tToX(t);
      if (x > W) break;
      if (pv !== null && x >= SIG_X) {{
        const ly = pv ? y+2 : y+h-2;
        if (first) {{ ctx.moveTo(Math.max(SIG_X,px), ly); first=false; }}
        else ctx.lineTo(Math.max(SIG_X,px), ly);
        ctx.lineTo(Math.max(SIG_X,x), ly);
        const ny = v ? y+2 : y+h-2;
        ctx.lineTo(Math.max(SIG_X,x), ny);
      }}
      pv = v; px = x;
    }}
    if (pv !== null) {{
      const ly = pv ? y+2 : y+h-2;
      ctx.lineTo(W, ly);
    }}
    ctx.stroke();
  }} else {{
    // Bus: draw trapezoid transitions with hex values
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.2;
    const pts = [];
    for (const [t, v] of tl) {{
      const x = Math.max(SIG_X, tToX(t));
      if (x > W) break;
      pts.push([x, v]);
    }}
    pts.push([W, pts.length ? pts[pts.length-1][1] : 0]);

    const MID = y + h/2;
    ctx.beginPath();
    for (let i = 0; i < pts.length-1; i++) {{
      const [x0,v] = pts[i];
      const [x1,v2] = pts[i+1];
      const d = Math.min(4, (x1-x0)/3);
      ctx.moveTo(x0, MID);
      ctx.lineTo(x0+d, y+2); ctx.lineTo(x1-d, y+2); ctx.lineTo(x1, MID);
      ctx.lineTo(x1-d, y+h-2); ctx.lineTo(x0+d, y+h-2); ctx.closePath();
      // fill
      ctx.fillStyle = (v===0) ? '#1a3a1a' : '#1a1a3a';
      ctx.fill();
      ctx.stroke();
      ctx.beginPath();
      // label
      const mid = (x0+x1)/2;
      const span = x1-x0;
      if (span > 50) {{
        ctx.fillStyle = '#ddd';
        ctx.font = '10px monospace';
        const hex = '0x' + v.toString(16).toUpperCase().padStart(2,'0');
        ctx.fillText(hex, mid - ctx.measureText(hex).width/2, MID+4);
      }}
    }}
    ctx.strokeStyle = color;
    ctx.stroke();
  }}
  ctx.restore();
}}

function drawAnnotations() {{
  ANNOTS.forEach((a, i) => {{
    const x = tToX(a.t);
    if (x < 90 || x > C.width) return;
    ctx.strokeStyle = '#555';
    ctx.lineWidth = 0.5;
    ctx.setLineDash([3,3]);
    ctx.beginPath();
    ctx.moveTo(x, 0); ctx.lineTo(x, C.height);
    ctx.stroke();
    ctx.setLineDash([]);
  }});

  // Specials
  SPECIALS.forEach(s => {{
    const x = tToX(s.t || 0);
    if (x < 90 || x > C.width) return;
    ctx.strokeStyle = '#ffa500';
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4,2]);
    ctx.beginPath();
    ctx.moveTo(x, 0); ctx.lineTo(x, C.height);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = '#ffa500';
    ctx.font = 'bold 10px monospace';
    ctx.fillText(s.label, x+3, 15);
    ctx.fillStyle = '#ffa500aa';
    ctx.font = '9px monospace';
    ctx.fillText('C=' + s.count, x+3, 27);
  }});
}}

function drawTimeline() {{
  ctx.fillStyle = '#555';
  ctx.font = '9px monospace';
  const step = Math.pow(10, Math.floor(Math.log10((viewEnd-viewStart)/8)));
  for (let t = Math.ceil(viewStart/step)*step; t <= viewEnd; t += step) {{
    const x = tToX(t);
    if (x < 90) continue;
    ctx.fillStyle = '#555';
    ctx.fillRect(x, C.height-12, 1, 5);
    ctx.fillStyle = '#777';
    ctx.fillText(t >= 1000 ? (t/1000).toFixed(1)+'μs' : t+'ns', x+2, C.height-2);
  }}
}}

function draw() {{
  ctx.clearRect(0, 0, C.width, C.height);
  ctx.fillStyle = '#111';
  ctx.fillRect(0, 0, C.width, C.height);

  // Grid
  ctx.strokeStyle = '#222'; ctx.lineWidth = 0.5;
  const step = Math.pow(10, Math.floor(Math.log10((viewEnd-viewStart)/8)));
  for (let t = Math.ceil(viewStart/step)*step; t <= viewEnd; t+=step) {{
    const x = tToX(t);
    if (x < 90) continue;
    ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,C.height); ctx.stroke();
  }}

  drawAnnotations();
  drawSignal(CLK,   10,  35, 'clk',      '#569cd6', false);
  drawSignal(MW,    50,  35, 'MemWrite',  '#4ec9b0', false);
  drawSignal(ADDR, 90,  60, 'DataAdr',   '#c586c0', true);
  drawSignal(DATA, 155, 60, 'WriteData', '#dcdcaa', true);
  drawTimeline();

  // Cursor label top-right
  ctx.fillStyle = '#555';
  ctx.font = '10px monospace';
  const vspan = (viewEnd - viewStart).toFixed(0);
  ctx.fillText(`View: ${{viewStart.toFixed(0)}}–${{viewEnd.toFixed(0)}} ns  (span: ${{vspan}} ns)`, C.width - 280, 12);
}}

// Mouse drag
C.addEventListener('mousemove', e => {{
  const rect = C.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const t = viewStart + (x / C.width) * (viewEnd - viewStart);
  document.getElementById('cur_t').textContent = t.toFixed(1);
  if (dragging) {{
    const dt = (dragX0 - x) / C.width * dragV0Span;
    viewStart = Math.max(0, dragV0Start + dt);
    viewEnd   = viewStart + dragV0Span;
    if (viewEnd > MAX_T) {{ viewEnd = MAX_T; viewStart = Math.max(0, MAX_T - dragV0Span); }}
    draw();
  }}
}});
C.addEventListener('mousedown', e => {{
  dragging = true;
  dragX0      = e.clientX - C.getBoundingClientRect().left;
  dragV0Start = viewStart;
  dragV0Span  = viewEnd - viewStart;
}});
C.addEventListener('mouseup',   () => dragging = false);
C.addEventListener('mouseleave',() => dragging = false);
C.addEventListener('wheel', e => {{
  e.preventDefault();
  zoom(e.deltaY > 0 ? 1.2 : 0.8);
}}, {{passive:false}});

// Touch
let lastTouchDist = null;
let touchStartX   = null;
let touchV0Start  = 0;
let touchV0Span   = 0;

C.addEventListener('touchstart', e => {{
  if (e.touches.length === 1) {{
    touchStartX  = e.touches[0].clientX;
    touchV0Start = viewStart;
    touchV0Span  = viewEnd - viewStart;
  }}
  if (e.touches.length === 2) {{
    lastTouchDist = Math.hypot(
      e.touches[0].clientX - e.touches[1].clientX,
      e.touches[0].clientY - e.touches[1].clientY);
  }}
  e.preventDefault();
}}, {{passive:false}});

C.addEventListener('touchmove', e => {{
  if (e.touches.length === 1 && touchStartX !== null) {{
    // 1 палец — скролл
    const dx = touchStartX - e.touches[0].clientX;
    const dt = dx / C.width * touchV0Span;
    viewStart = Math.max(0, touchV0Start + dt);
    viewEnd   = viewStart + touchV0Span;
    if (viewEnd > MAX_T) {{ viewEnd = MAX_T; viewStart = Math.max(0, MAX_T - touchV0Span); }}
    draw();
  }} else if (e.touches.length === 2) {{
    // 2 пальца — zoom
    const d = Math.hypot(
      e.touches[0].clientX - e.touches[1].clientX,
      e.touches[0].clientY - e.touches[1].clientY);
    if (lastTouchDist) zoom(lastTouchDist / d);
    lastTouchDist = d;
  }}
  e.preventDefault();
}}, {{passive:false}});

C.addEventListener('touchend', () => {{
  lastTouchDist = null;
  touchStartX   = null;
}});

window.addEventListener('resize', resize);
resize();
</script>
</body>
</html>
"""

with open(HTML_OUT, "w") as f:
    f.write(HTML)

print(f"Done! Open in browser: {HTML_OUT}")
print(f"COUNT writes found: {len(count_writes)}")
for a in annots[:5]:
    print(f"  COUNT[{a['idx']}] @ {a['t']} ns = {a['data']}")
