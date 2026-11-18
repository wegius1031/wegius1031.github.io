// Identity is independent of the editable display name. No fuzzy financial-asset merges.
export const normalizedName=name=>String(name||'').normalize('NFKC').replace(/\s+/g,'').toLocaleLowerCase('en-US');
export const validInstrumentId=id=>typeof id==='string'&&/^[A-Za-z0-9_-]{1,100}$/.test(id);
function hash(text){let n=2166136261;for(const c of text)n=Math.imul(n^c.charCodeAt(0),16777619);return(n>>>0).toString(16).padStart(8,'0')}
function initialId(snapshot,index){return'asset_'+snapshot.id.slice(0,64)+'_'+index+'_'+hash(snapshot.id)}
const category=h=>h.category==='积存金'||/积存金/.test(h.name||'')?'积存金':'基金';
export function instrumentCatalogue(doc){
 const entries=new Map(),snapshots=[...(doc.snapshots||[])].sort((a,b)=>a.date.localeCompare(b.date)||a.id.localeCompare(b.id));
 function named(name){const key=normalizedName(name);return[...entries.values()].filter(e=>e.names.has(key))}
 for(const snapshot of snapshots)for(let i=0;i<snapshot.holdings.length;i++){
  const h=snapshot.holdings[i],matches=named(h.name);let id=validInstrumentId(h.instrumentId)?h.instrumentId:matches.length===1?matches[0].id:initialId(snapshot,i);
  const existing=entries.get(id),names=existing?.names||new Set();names.add(normalizedName(h.name));
  entries.set(id,{id,name:h.name,category:category(h),names,lastSnapshot:snapshot.date,source:'snapshot'});
 }
 for(const r of doc.records||[]){if(!['buy','sell','dividend'].includes(r.kind)||!validInstrumentId(r.instrumentId)||!r.instrument)continue;const e=entries.get(r.instrumentId);if(e)e.names.add(normalizedName(r.instrument));else entries.set(r.instrumentId,{id:r.instrumentId,name:r.instrument,category:r.category==='积存金'?'积存金':'基金',names:new Set([normalizedName(r.instrument)]),source:'record'});}
 return[...entries.values()];
}
export function identifyInstrument(catalogue,record){if(validInstrumentId(record.instrumentId))return catalogue.find(x=>x.id===record.instrumentId)||null;const key=normalizedName(record.instrument||record.name);if(!key)return null;const matches=catalogue.filter(e=>e.names.has(key));return matches.length===1?matches[0]:null}
export function chooseInstrument(catalogue,id,newName='',newCategory='基金',createId){
 if(id&&id!=='__new__'){const entry=catalogue.find(e=>e.id===id);if(!entry)throw Error('该持仓已更新，请重新选择');return{instrumentId:entry.id,instrument:entry.name,category:entry.category}}
 if(id!=='__new__')throw Error('请先选择已有持仓，或选择“新增标的”');
 const name=newName.trim();if(!name||name.length>160)throw Error('请填写不超过160字的标的名称');const key=normalizedName(name),matches=catalogue.filter(e=>e.names.has(key));
 if(matches.length>1)throw Error('存在同名持仓，请在列表中明确选择');
 if(matches.length===1)return{instrumentId:matches[0].id,instrument:matches[0].name,category:matches[0].category};
 const instrumentId=createId();if(!validInstrumentId(instrumentId)||catalogue.some(e=>e.id===instrumentId))throw Error('标的编号无效，请重试');
 return{instrumentId,instrument:name,category:newCategory==='积存金'?'积存金':'基金'};
}
export function linkInstruments(doc){const out=structuredClone(doc),catalogue=instrumentCatalogue(out);for(const s of out.snapshots){const seen=new Set();for(const h of s.holdings){const e=identifyInstrument(catalogue,h);if(!e)continue;if(seen.has(e.id))throw Error('同一快照中重复添加了同一持仓，请合并核对后保存');seen.add(e.id);h.instrumentId=e.id}}
 for(const r of out.records){if(!['buy','sell','dividend'].includes(r.kind))continue;const e=identifyInstrument(catalogue,r);if(!e)continue;r.instrumentId=e.id;if(r.instrument!==e.name){r.instrumentOriginal??=r.instrument;r.instrument=e.name}if(r.kind!=='dividend')r.category=e.category}return out}
export function instrumentActivity(doc,start,end){const catalogue=instrumentCatalogue(doc),totals=new Map(catalogue.map(e=>[e.id,{buy:0,sell:0,dividend:0,count:0}]));for(const r of doc.records||[]){if(r.date<start||r.date>end)continue;const e=identifyInstrument(catalogue,r);if(!e)continue;const t=totals.get(e.id);if(r.kind==='buy')t.buy+=r.amount;else if(r.kind==='sell')t.sell+=r.amount-(r.fee||0);else if(r.kind==='dividend')t.dividend+=r.amount;else continue;t.count++}return totals}
