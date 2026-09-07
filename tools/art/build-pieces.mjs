// Export the approved Canvas paths without changing their geometry or palette.
import fs from 'node:fs';
import vm from 'node:vm';
const source = fs.readFileSync(new URL('./approved-piece-v4.html', import.meta.url), 'utf8');
const body = source.slice(source.indexOf('    const colors='), source.indexOf('    function label('));
let output = [], stack = [], transform = '';
const c = {
 save() { stack.push(transform); }, restore() { transform = stack.pop(); },
 translate(x,y) { transform += ` translate(${x} ${y})`; },
 scale(x,y) { transform += ` scale(${x} ${y})`; },
 rotate(a) { transform += ` rotate(${a*180/Math.PI})`; },
 beginPath() { this.current = ''; },
 arc(x,y,r) { this.ellipse(x,y,r,r); },
 ellipse(x,y,rx,ry) { this.current = `M${x-rx} ${y} a${rx} ${ry} 0 1 0 ${rx*2} 0 a${rx} ${ry} 0 1 0 ${-rx*2} 0`; },
 fill(path) { output.push(`<path d="${path?.d ?? this.current}" transform="${transform}" fill="${this.fillStyle}"/>`); },
 stroke(path) { output.push(`<path d="${path?.d ?? this.current}" transform="${transform}" fill="none" stroke="${this.strokeStyle}" stroke-width="${this.lineWidth}" stroke-linecap="round" stroke-linejoin="round"/>`); }
};
const ctx = vm.createContext({c, state:{silhouette:false}, Path2D:class {constructor(d){this.d=d;}}});
vm.runInContext(body + ';globalThis.render=piece;',ctx);
const dest = new URL('../../ui/art/pieces/',import.meta.url);
fs.mkdirSync(dest,{recursive:true});
for (const kind of ['guard','crossbow','assassin','standard']) for (const enemy of [false,true]) {
 output=[]; stack=[]; transform='';
 for(let frame=0;frame<9;frame++) ctx.render(kind,110+220*frame,240,1,enemy?-1:1,enemy,frame/8);
 fs.writeFileSync(new URL(`${kind}-${enemy?'enemy':'ally'}.svg`,dest),`<svg xmlns="http://www.w3.org/2000/svg" width="1980" height="252" viewBox="0 0 1980 252">${output.join('\n')}</svg>\n`);
}
console.log('Exported eight approved vector chess pieces.');
