export const designNotes = '以盾、横弩、尖刃和旗面的单一主轮廓构成玉石棋子，用一体根部、宽阔切面与极少金饰替代人物细节。';

const JADE = { body: '#80a596', light: '#b5c5a6', shade: '#41685f', deep: '#2c4943', gold: '#c6ad72', ink: '#142825' };
const CLAY = { body: '#be7961', light: '#e0ad87', shade: '#884f40', deep: '#59392f', gold: '#d1b176', ink: '#30251f' };

function shape(ctx, p, fill, stroke, width = 3) {
  const path = new Path2D(p);
  ctx.fillStyle = fill;
  ctx.fill(path);
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = width;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke(path);
  }
}

// Every silhouette grows out of this same low, solid chess plinth.
function base(ctx, c) {
  shape(ctx, 'M-33 -29 Q-39 -23 -43 -13 L-43 -9 Q-42 0 0 0 Q42 0 43 -9 L43 -13 Q39 -23 33 -29 Z', c.body, c.ink);
  shape(ctx, 'M-43 -13 Q0 1 43 -13 L43 -9 Q42 0 0 0 Q-42 0 -43 -9 Z', c.shade);
  shape(ctx, 'M-33 -29 Q0 -20 33 -29 Q27 -37 24 -40 L-24 -40 Q-27 -37 -33 -29 Z', c.light, c.ink, 2.5);
  shape(ctx, 'M-30 -26 Q0 -18 30 -26 L32 -22 Q0 -14 -32 -22 Z', c.gold);
}

function shield(ctx, c, p) {
  ctx.save();
  ctx.translate(0, -31);
  ctx.rotate(p * 0.105);
  // The shoulder and neck are a taper of the shield, not a separate person.
  shape(ctx, 'M-25 0 Q-16 -26 -20 -42 L-32 -101 L-14 -131 L22 -129 L41 -105 L36 -55 Q29 -26 25 0 Z', c.body, c.ink, 3.2);
  shape(ctx, 'M-14 -131 L-5 -105 L-9 -50 L-20 -19 L-25 0 Q-16 -26 -20 -42 L-32 -101 Z', c.shade);
  shape(ctx, 'M-5 -105 L22 -129 L41 -105 L36 -55 Q31 -28 12 -14 L-9 -50 Z', c.light);
  // A single vast shield face, clipped corners and a point at the root.
  shape(ctx, 'M-5 -109 L24 -121 L42 -101 L38 -62 Q32 -38 12 -22 Q-7 -36 -13 -59 L-19 -91 Z', c.body, c.ink, 3);
  shape(ctx, 'M24 -121 L42 -101 L38 -62 Q32 -38 12 -22 L16 -85 Z', c.light);
  shape(ctx, 'M-5 -109 L24 -121 L22 -114 L-3 -102 L-13 -88 L-19 -91 Z', c.gold);
  ctx.restore();
}

function crossbow(ctx, c, p) {
  ctx.save();
  ctx.translate(-p * 5, -31);
  ctx.rotate(-p * 0.035);
  shape(ctx, 'M-24 0 Q-12 -29 -16 -61 L-23 -86 L-13 -124 L2 -132 L18 -119 L19 -86 Q10 -60 18 -28 L25 0 Z', c.body, c.ink, 3.2);
  shape(ctx, 'M2 -132 L18 -119 L19 -86 Q10 -60 18 -28 L25 0 L8 -3 L-1 -67 L-6 -96 Z', c.light);
  shape(ctx, 'M-23 -86 L-13 -124 L2 -132 L-6 -96 L-1 -67 L-12 -17 L-24 0 Q-12 -29 -16 -61 Z', c.shade);
  // Broad transverse bow and projecting stock provide the rook-like profile.
  shape(ctx, 'M-48 -112 L-30 -103 L-10 -103 L-4 -108 L43 -108 L49 -100 L43 -92 L-3 -92 L-11 -97 L-32 -97 L-48 -85 L-44 -98 Z', c.body, c.ink, 3);
  shape(ctx, 'M-48 -112 L-30 -103 L-10 -103 L-4 -108 L43 -108 L49 -100 L6 -100 L-5 -102 L-30 -99 Z', c.light);
  shape(ctx, 'M-7 -108 L0 -108 L0 -92 L-7 -94 Z', c.gold);
  if (p > 0) {
    ctx.globalAlpha *= p;
    const tip = 47 + p * 10;
    shape(ctx, `M${tip - 12} -117 L${tip + 3} -117 L${tip - 2} -121 L${tip + 8} -115 L${tip - 2} -110 L${tip + 3} -114 L${tip - 12} -114 Z`, c.gold, c.ink, 1.5);
  }
  ctx.restore();
}

function assassin(ctx, c, p) {
  ctx.save();
  ctx.translate(0, -31);
  ctx.rotate(p * 0.19);
  // An asymmetric pointed blade; no face, hood cavity or cloth seams.
  shape(ctx, 'M-25 0 L-16 -31 L-24 -67 L-16 -105 L15 -134 L11 -101 L28 -84 L18 -68 L8 -66 L13 -36 L25 0 Z', c.body, c.ink, 3.2);
  shape(ctx, 'M15 -134 L11 -101 L28 -84 L18 -68 L8 -66 L13 -36 L25 0 L8 -5 L-1 -42 L-7 -71 L2 -103 Z', c.light);
  shape(ctx, 'M-16 -105 L15 -134 L2 -103 L-7 -71 L-1 -42 L-13 -15 L-25 0 L-16 -31 L-24 -67 Z', c.shade);
  // One forward blade fused to the body; its negative space reads at 48%.
  shape(ctx, 'M-5 -63 L43 -109 L37 -72 L13 -48 L4 -32 L-7 -39 Z', c.light, c.ink, 3);
  shape(ctx, 'M43 -109 L37 -72 L13 -48 L4 -32 L-1 -43 L23 -71 Z', c.body);
  shape(ctx, 'M-9 -53 L-2 -60 L17 -41 L11 -35 Z', c.gold, c.ink, 2);
  ctx.restore();
}

function banner(ctx, c, p) {
  ctx.save();
  ctx.translate(0, -31);
  ctx.rotate(-0.04 + p * 0.075);
  shape(ctx, 'M-25 0 Q-13 -23 -12 -44 L-12 -140 L-5 -151 L2 -140 L2 -44 Q4 -23 25 0 Z', c.body, c.ink, 3.2);
  shape(ctx, 'M-5 -151 L2 -140 L2 -44 Q4 -23 25 0 L6 -6 L-4 -39 Z', c.light);
  shape(ctx, 'M-25 0 Q-13 -23 -12 -44 L-12 -140 L-5 -151 L-4 -39 L-13 -12 Z', c.shade);
  const wave = p * 7;
  shape(ctx, `M0 -139 Q18 ${-145 - wave * 0.25} 36 -135 L50 ${-138 + wave * 0.5} L40 ${-112 + wave} L49 ${-90 + wave} Q29 ${-81 - wave * 0.5} 13 -89 L0 -89 Z`, c.body, c.ink, 3.2);
  shape(ctx, `M0 -139 Q18 ${-145 - wave * 0.25} 36 -135 L50 ${-138 + wave * 0.5} L40 ${-128 + wave * 0.2} Q20 ${-137 - wave * 0.2} 0 -130 Z`, c.light);
  shape(ctx, `M0 -89 L0 -105 Q24 ${-102 - wave * 0.3} 49 ${-90 + wave} Q29 ${-81 - wave * 0.5} 13 -89 Z`, c.shade);
  shape(ctx, 'M0 -136 L6 -137 L6 -89 L0 -89 Z', c.gold);
  ctx.restore();
}

const pieces = { shield, crossbow, assassin, banner };

export function drawPiece(ctx, kind, x, y, scale, direction, enemy, pose = 0) {
  const p = Math.max(0, Math.min(1, pose));
  const c = enemy ? CLAY : JADE;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(scale * direction, scale);
  (pieces[kind] || shield)(ctx, c, p);
  base(ctx, c);
  ctx.restore();
}

