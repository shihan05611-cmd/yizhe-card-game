export const designNotes = '以青玉与陶土的厚切几何体构成四种兵器：甲卒是叠盾，机弩是张弓与箭轨，刺客是斜刃，旗兵是立柱与旗面；用重心、负形和哑光切面保持小尺寸辨识。';

const PALETTES = {
  jade: { ink: '#142825', face: '#80a596', light: '#b5c5a6', side: '#41685f', dark: '#2c4943', gold: '#c6ad72', grain: '#e4dec0' },
  clay: { ink: '#30251f', face: '#be7961', light: '#e0ad87', side: '#884f40', dark: '#59392f', gold: '#d1b176', grain: '#efcfaa' },
};

function path(ctx, points) {
  ctx.beginPath();
  ctx.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
  ctx.closePath();
}

function polygon(ctx, points, fill, stroke, width = 2) {
  path(ctx, points);
  ctx.fillStyle = fill;
  ctx.fill();
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = width;
    ctx.stroke();
  }
}

function stroke(ctx, points, color, width = 1.4) {
  ctx.beginPath();
  ctx.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
}

// A fixed, clipped mineral grain: it never swims as the pose changes.
function grain(ctx, points, p) {
  ctx.save();
  path(ctx, points);
  ctx.clip();
  ctx.fillStyle = p.grain;
  ctx.globalAlpha *= 0.10;
  let seed = 3907;
  for (let i = 0; i < 180; i++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const px = -58 + (seed % 1170) / 10;
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const py = -182 + (seed % 1800) / 10;
    ctx.fillRect(px, py, 0.7 + (i % 3) * 0.25, 0.65);
  }
  ctx.restore();
}

function slab(ctx, points, p, muted = false, depth = 6) {
  const back = points.map(([x, y]) => [x - depth, y - depth * 0.62]);
  polygon(ctx, back, p.dark, p.ink, 2.6);
  for (let i = 0; i < points.length; i++) {
    const n = (i + 1) % points.length;
    polygon(ctx, [back[i], back[n], points[n], points[i]],
      points[n][0] > points[i][0] ? p.light : p.side, p.ink, 1.1);
  }
  const gradient = ctx.createLinearGradient(-35, -170, 35, -10);
  gradient.addColorStop(0, muted ? p.side : p.light);
  gradient.addColorStop(0.30, muted ? p.side : p.face);
  gradient.addColorStop(1, muted ? p.dark : p.side);
  polygon(ctx, points, gradient, p.ink, 2.4);
  grain(ctx, points, p);
}

function foot(ctx, p) {
  // Broad ground contact without a chess pedestal or a humanoid leg split.
  slab(ctx, [[-33,-15],[-16,-32],[20,-28],[36,-12],[29,-2],[-29,-2]], p, true, 3);
  stroke(ctx, [[-26,-12],[25,-12]], p.face, 1.3);
}

function shield(ctx, p, t) {
  foot(ctx, p);
  ctx.save();
  ctx.transform(1, 0, -0.095 * t, 1 - 0.025 * t, 0, 0);
  // Rear buttress and forward shield meet in one broad rooted mass.
  slab(ctx, [[-34,-127],[-17,-158],[4,-149],[11,-45],[-17,-13],[-33,-27]], p, true);
  slab(ctx, [[0,-159],[32,-148],[40,-105],[28,-51],[4,-16],[-12,-48],[-13,-117]], p);
  polygon(ctx, [[0,-156],[9,-146],[16,-97],[4,-22],[-8,-49],[-9,-115]], p.side);
  stroke(ctx, [[3,-151],[29,-143],[36,-105],[25,-56]], p.light, 1.8);
  // One broad inlay, legible even at battlefield scale.
  polygon(ctx, [[6,-121],[31,-115],[32,-107],[7,-113]], p.gold);
  stroke(ctx, [[14,-80],[11,-65]], p.ink, 1.25);
  ctx.restore();
}

function crossbow(ctx, p, t) {
  // The mounting wedge is also the root; no additional base or tiny joints.
  slab(ctx, [[-33,-3],[-39,-17],[-16,-114],[0,-132],[17,-111],[11,-43],[32,-12],[28,-3]], p, true, 4);
  polygon(ctx, [[-13,-106],[1,-123],[8,-107],[1,-39],[-25,-12]], p.side);
  stroke(ctx, [[-29,-9],[23,-9]], p.face, 1.3);
  ctx.save();
  ctx.translate(-7 * t, 2 * t);
  // A thick open bow makes a large, unmistakable negative space.
  slab(ctx, [[1,-160],[15,-155],[40,-126],[39,-113],[15,-78],[0,-73],
    [20,-112],[22,-122]], p, false, 5);
  polygon(ctx, [[5,-154],[14,-151],[35,-126],[30,-123]], p.light);
  stroke(ctx, [[2,-155],[-15 + 27*t,-118],[2,-79]], p.gold, 1.7);
  slab(ctx, [[-41,-124],[45,-124],[55,-117],[45,-111],[-40,-111],[-45,-116]], p, false, 4);
  polygon(ctx, [[-34,-120],[37,-120],[45,-117],[37,-115],[-34,-115]], p.dark);
  stroke(ctx, [[-26,-118],[41,-118]], p.gold, 2.3);
  ctx.restore();
}

function assassin(ctx, p, t) {
  // A low triangular counterweight and one long asymmetric knife, no head/body.
  slab(ctx, [[-32,-3],[-38,-15],[-27,-89],[-4,-126],[16,-106],[12,-62],[30,-12],[24,-3]], p, true, 5);
  polygon(ctx, [[-24,-84],[-5,-116],[3,-101],[-7,-61],[-30,-12]], p.side);
  stroke(ctx, [[-25,-9],[20,-9]], p.face, 1.3);
  ctx.save();
  ctx.translate(-9, -46);
  ctx.rotate(0.24 * t);
  // A hooked spine leaves an angular open notch above the root.
  slab(ctx, [[-13,13],[-9,-25],[3,-68],[38,-116],[30,-69],[13,-28],[1,10]], p, false, 5);
  polygon(ctx, [[38,-116],[30,-69],[13,-28],[1,10],[-3,8],[5,-31],[20,-75]], p.light);
  polygon(ctx, [[-9,-24],[-1,-36],[14,-29],[10,-18]], p.gold);
  stroke(ctx, [[-8,-27],[4,-65],[29,-101]], p.side, 1.5);
  ctx.restore();
}

function banner(ctx, p, t) {
  foot(ctx, p);
  ctx.save();
  ctx.transform(1, 0, -0.028 * t, 1, 0, 0);
  // A single tapering pillar carries one solid, folded pennant slab.
  slab(ctx, [[-20,-16],[-22,-171],[-15,-179],[-7,-174],[0,-17]], p, true, 4);
  stroke(ctx, [[-14,-170],[-8,-28]], p.gold, 2);
  const lift = 5 * t;
  slab(ctx, [[-8,-165],[43,-159-lift],[51,-117-lift],[26,-125-lift],[-5,-111]], p, false, 5);
  polygon(ctx, [[-5,-160],[11,-148],[14,-121],[-3,-114]], p.side);
  polygon(ctx, [[11,-148],[43,-155-lift],[46,-132-lift],[24,-138]], p.face);
  stroke(ctx, [[-3,-160],[39,-155-lift]], p.light, 1.8);
  // Wide diagonal seam reads as a flag fold rather than an electronic emblem.
  stroke(ctx, [[15,-147],[36,-141-lift]], p.gold, 3.5);
  ctx.restore();
}

export function drawPiece(ctx, kind, x, y, scale, direction, enemy, pose = 0) {
  const t = Math.max(0, Math.min(1, pose));
  const eased = t * t * (3 - 2 * t);
  const p = enemy ? PALETTES.clay : PALETTES.jade;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(scale * direction, scale);
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  if (kind === 'shield') shield(ctx, p, eased);
  else if (kind === 'crossbow') crossbow(ctx, p, eased);
  else if (kind === 'assassin') assassin(ctx, p, eased);
  else if (kind === 'banner') banner(ctx, p, eased);
  ctx.restore();
}
