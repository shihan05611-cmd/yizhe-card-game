export const designNotes = '沿用青玉与陶土切面，刺客改为围绕留白错开的三片薄棱体，以窄接地、偏置重心和片间前探表达灵巧，不再模仿人物或现实兵器。';

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
  // Three offset laminae describe a broken spiral around empty space.
  // The only ground contact is eight units wide; no plinth or broad counterweight.
  ctx.save();
  ctx.transform(1, 0, -0.055 * t, 1, 0, 0);
  slab(ctx, [[-8,-3],[-16,-17],[-21,-55],[-12,-90],[-2,-99],[-6,-57],[3,-19],[0,-3]], p, true, 2);
  polygon(ctx, [[-12,-86],[-4,-96],[-10,-56],[-2,-18],[0,-5],[-5,-12],[-16,-55]], p.face);
  stroke(ctx, [[-5,-10],[-2,-4]], p.light, 1.2);
  ctx.restore();

  // The rear sheet twists a little later than the leading one: a poised,
  // non-mechanical opening gesture, reversible continuously with the pose.
  ctx.save();
  ctx.translate(-2 + 6 * t, -129 + 3 * t);
  ctx.rotate(0.095 * t);
  ctx.translate(2, 129);
  slab(ctx, [[-28,-116],[-19,-149],[11,-167],[22,-157],[-4,-130],[-12,-105]], p, false, 2.2);
  polygon(ctx, [[-19,-147],[11,-165],[16,-158],[-8,-136],[-25,-119]], p.light);
  polygon(ctx, [[-8,-136],[16,-158],[20,-157],[-4,-130],[-12,-108]], p.side);
  stroke(ctx, [[-18,-139],[-10,-145]], p.gold, 2.2);
  ctx.restore();

  // The separated forward sheet is an oblique fold rather than a knife:
  // a blunt high corner, unequal sides, and a broad central cut plane.
  ctx.save();
  ctx.translate(17 + 12 * t, -102 + 5 * t);
  ctx.rotate(0.11 * t);
  ctx.translate(-17, 102);
  slab(ctx, [[32,-143],[39,-125],[18,-78],[3,-63],[9,-101]], p, false, 2);
  polygon(ctx, [[32,-140],[35,-124],[14,-80],[5,-66],[15,-100]], p.light);
  polygon(ctx, [[35,-124],[37,-125],[17,-79],[5,-66],[14,-80]], p.side);
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
