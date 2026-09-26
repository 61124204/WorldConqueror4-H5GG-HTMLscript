-- Offline GameGuardian API mock. Does NOT access Android or validate game offsets.
local mem,results,writes,paused,alerts,saved={}, {},0,false,{},{}
local target={pid=100,packageName='test.wc4',versionCode=353,versionName='test',x64=true}
local failWriteAt,failAlways,shortPage,badRead,duplicatePage,afterAlert=nil,false,false,false,false,nil
local afterRead,afterWrite=nil,nil
local answer=1
local calls={}
gg={TYPE_BYTE=1,TYPE_WORD=2,TYPE_DWORD=4,TYPE_QWORD=32,TYPE_FLOAT=16,TYPE_DOUBLE=64,SIGN_EQUAL=0,
 REGION_ANONYMOUS=32,REGION_C_ALLOC=4,REGION_C_BSS=16,REGION_C_DATA=8,REGION_JAVA_HEAP=2}
function gg.getTargetInfo() return target end
function gg.getValues(q)
  if badRead then return 'read failure' end
  local out={}
  for i,p in ipairs(q) do
    if mem[p.address]==nil then return 'unmapped address' end
    out[i]={address=p.address,flags=p.flags,value=tostring(mem[p.address])}
  end
  if afterRead then local fn=afterRead; afterRead=nil; fn() end
  return out
end
function gg.clearResults() results={} end
function gg.searchNumber(n,flags,encrypted,sign,first,last)
  assert(flags==gg.TYPE_DWORD and encrypted==false and first==0 and last==-1)
  calls.search={first=first,last=last}; results={}
  for a,v in pairs(mem) do if v==tonumber(n) then results[#results+1]={address=a,flags=flags,value=tostring(v)} end end
  table.sort(results,function(a,b) return a.address<b.address end)
end
function gg.getResultsCount() return #results end
function gg.getResults(n,skip)
  calls.pages=(calls.pages or 0)+1
  skip=skip or 0
  if duplicatePage then skip=0 end
  local out={}
  for i=skip+1,skip+n-(shortPage and 1 or 0) do out[#out+1]=results[i] end
  return out
end
function gg.setValues(q)
  writes=writes+1
  for i,p in ipairs(q) do
    if failAlways or (failWriteAt and i==failWriteAt) then failWriteAt=nil; return 'injected write failure' end
    mem[p.address]=tonumber(p.value)
  end
  if afterWrite then local fn=afterWrite; afterWrite=nil; fn() end
  return nil -- Verify by reading back; do not require boolean true.
end
function gg.isProcessPaused() return paused end
function gg.processPause() paused=true; return true end
function gg.processResume() paused=false; calls.resumes=(calls.resumes or 0)+1; return true end
function gg.getListItems() return saved end
function gg.alert(s,...)
  alerts[#alerts+1]=s
  if afterAlert then local fn=afterAlert; afterAlert=nil; fn() end
  return answer
end
function gg.toast() end
function gg.getFile() return './WorldConqueror4_GG.lua' end
function gg.getRanges() return 0 end
function gg.setRanges() end
function gg.setVisible() end
function gg.isVisible() return true end
function gg.sleep() end
WC4_GG_TEST=true
local C=dofile('WorldConqueror4_GG.lua')
local passed,failed=0,0
local function reset()
  mem={}; results={}; writes=0; paused=false; alerts={}; saved={}; calls={}
  target={pid=100,packageName='test.wc4',versionCode=353,versionName='test',x64=true}
  failWriteAt=nil; failAlways=false; shortPage=false; badRead=false; duplicatePage=false
  afterAlert=nil; afterRead=nil; afterWrite=nil; answer=1
  C.bind(); C.state.batch=256; C.state.maxResults=200000; C.state.catalogs={}
end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function errors(fn,needle)
  local ok,err=pcall(fn); assert(not ok,'Expected rejection')
  if needle then assert(tostring(err):find(needle,1,true),tostring(err)) end
end
local function test(name,fn)
  reset(); local ok,err=pcall(fn)
  if ok then passed=passed+1; print('PASS '..name)
  else failed=failed+1; print('FAIL '..name..': '..tostring(err)) end
end
local function put(base,spec)
  for _,p in ipairs(spec) do mem[base+p[1]]=C.signed(p[2]) end
end
local function simple()
  mem[0x1000]=10; mem[0x1004]=20
  return {{address=0x1000,value=11},{address=0x1004,value=21}}
end

test('integer validation and boundaries',function()
  for _,v in ipairs({'',' ','1.0','1e3','2147483648','nan','--1'}) do errors(function() C.integer(v) end) end
  eq(C.integer('-2147483648'),-2147483648); eq(C.integer(' +12 '),12)
end)
test('XOR reversible at boundaries',function()
  for _,v in ipairs({0,1,640,999999,2147483647,-2147483648,-1}) do eq(C.encode(C.encode(v)),v) end
  eq(C.encode(0),518867); eq(C.encode(640),518227)
end)
test('signed U32 normalization',function() eq(C.signed(4294967295),-1); eq(C.signed(2147483648),-2147483648) end)
test('RGBA little-endian color and signed DWORD',function()
  eq(C.color('#B48750'),-11499596); eq(C.colorText(C.color('#B48750')),'#B48750')
  eq(C.color('#FFFFFF'),-1); errors(function() C.color('#FFFF') end)
end)
test('JSON BOM, nesting, escaped strings, false and null',function()
  local t=C.json('\239\187\191{"a":[0,-2,3.5,1e2,false,null],"b":"汉字\\n\\\""}')
  eq(t.a[4],100); eq(t.a[5],false); eq(t.a[6],C.JSON_NULL); eq(t.b,'汉字\n"')
end)
test('JSON Unicode escapes and surrogate pair',function()
  eq(C.json('"\\u4e16\\u754c"'),'世界'); eq(C.json('"\\uD83D\\uDE00"'),'😀')
end)
test('JSON rejects invalid and executable text',function()
  for _,t in ipairs({'return os.execute("id")','[1,]','{"a":1,"a":2}','01','1.','"\\uD800"','true garbage','{"x":}','[+1]'}) do errors(function() C.json(t) end) end
end)
test('JSON size and nesting limits',function()
  errors(function() C.json(string.rep(' ',2097153)) end)
  errors(function() C.json(string.rep('[',66)..'0'..string.rep(']',66)) end)
end)
test('search reaches matches beyond first 512 candidates',function()
  for i=1,900 do mem[0x1000+i*16]=100; mem[0x1004+i*16]=i==850 and 37500 or 0 end
  local a=C.search(100,{{0,100},{4,37500}})
  eq(#a,1); eq(a[1],0x1000+850*16); eq(calls.pages,4); eq(writes,0)
end)
test('late duplicate prevents false uniqueness',function()
  for i=1,900 do mem[0x1000+i*16]=100; mem[0x1004+i*16]=(i==2 or i==850) and 37500 or 0 end
  local a=C.search(100,{{0,100},{4,37500}}); eq(#a,2); errors(function() C.unique(a) end); eq(writes,0)
end)
test('64-bit address above old iOS search limit',function()
  local a=0x7000001000; put(a,{{0,77},{4,88}})
  eq(C.unique(C.search(77,{{0,77},{4,88}})),a); eq(calls.search.last,-1)
end)
test('result cap aborts whole search',function()
  for i=1,20 do mem[i*4]=7 end; C.state.maxResults=10
  errors(function() C.search(7) end); eq(writes,0)
end)
test('short candidate page aborts',function()
  mem[0x1000]=7; shortPage=true; errors(function() C.search(7) end); eq(writes,0)
end)
test('duplicate candidate page aborts',function()
  C.state.batch=1; mem[0x1000]=7; mem[0x1004]=7; duplicatePage=true
  errors(function() C.search(7) end); eq(writes,0)
end)
test('unreadable candidate aborts instead of disappearing',function()
  mem[0x1000]=7; errors(function() C.search(7,{{4,8}}) end); eq(writes,0)
end)
test('empty result cannot be written',function() eq(#C.search(7),0); errors(function() C.unique({}) end); eq(writes,0) end)
test('panel offsets and current-star signature',function()
  local sp=C.panelSpec(1001,{3,3,0,5,0,1})
  eq(sp[2][1],0x54); eq(sp[7][1],0x68); put(0x1000,sp)
  eq(C.unique(C.search(1001,sp)),0x1000)
end)
test('slot lookup checks all twelve catalog attributes',function()
  local g={id=1001,initial={march=3,infantry=3,armor=0,artillery=5,navy=0,airForce=1},maximum={march=4,infantry=5,armor=0,artillery=5,navy=0,airForce=3}}
  local sp=C.slotSpec(g); eq(#sp,13); eq(sp[2][1],0x68); eq(sp[13][1],0x94)
  put(0x1000,sp); put(0x2000,sp); mem[0x2094]=2
  eq(C.unique(C.search(1001,sp)),0x1000)
end)
test('resource triple plus strict country color',function()
  local sp=C.resourceSpec({520,190,30}); sp[#sp+1]={C.profile.color,C.color('#B4FFDC')}
  put(0x1000,sp); put(0x2000,sp); mem[0x2094]=C.color('#96FFBE')
  eq(C.unique(C.search(C.encode(520),sp)),0x1000)
end)
test('write, readback and LIFO undo with nil API success',function()
  local ch=simple(); assert(C.transaction('test',ch,nil,false)); eq(mem[0x1000],11); eq(#C.state.history,1); eq(paused,false)
  C.undo(); eq(mem[0x1000],10); eq(mem[0x1004],20); eq(#C.state.history,0)
end)
test('cancel leaves memory unchanged',function()
  local ch=simple(); answer=2; eq(C.transaction('cancel',ch),false); eq(writes,0)
end)
test('stale guard rejects before write',function()
  local ch=simple(); errors(function() C.transaction('stale',ch,{{address=0x1000,value=99}},false) end); eq(writes,0)
end)
test('confirmation race rechecks original values',function()
  local ch=simple(); afterAlert=function() mem[0x1000]=99 end
  errors(function() C.transaction('race',ch) end); eq(writes,0); eq(paused,false)
end)
test('partial write failure restores all targets',function()
  local ch=simple(); failWriteAt=2; errors(function() C.transaction('partial',ch,nil,false) end)
  eq(mem[0x1000],10); eq(mem[0x1004],20); eq(C.state.pending,nil); eq(#C.state.history,0); eq(paused,false)
end)
test('failed rollback blocks edits and keeps recovery record',function()
  local ch=simple(); failAlways=true; errors(function() C.transaction('failure',ch,nil,false) end)
  assert(C.state.pending); eq(paused,false); errors(function() C.transaction('blocked',ch,nil,false) end)
  failAlways=false; C.recover(); eq(C.state.pending,nil); eq(mem[0x1000],10)
end)
test('readback mismatch triggers rollback',function()
  local original=gg.setValues; local first=true
  gg.setValues=function(q)
    if first then first=false; writes=writes+1; mem[q[1].address]=123; return nil end
    return original(q)
  end
  local ch=simple(); local ok=pcall(function() C.transaction('mismatch',ch,nil,false) end)
  gg.setValues=original; eq(ok,false); eq(mem[0x1000],10); eq(C.state.pending,nil)
end)
test('user-paused process stays paused',function()
  local ch=simple(); paused=true; C.transaction('paused',ch,nil,false); eq(paused,true)
end)
test('failed pause prevents writes',function()
  local original=gg.processPause; gg.processPause=function() return false end
  local ch=simple(); local ok=pcall(function() C.transaction('no pause',ch,nil,false) end)
  gg.processPause=original; eq(ok,false); eq(writes,0)
end)
test('foreign overlapping QWORD freeze is preserved and rejected',function()
  local ch=simple(); saved={{address=0x0FFC,flags=gg.TYPE_QWORD,freeze=true,value=1}}
  errors(function() C.transaction('frozen',ch,nil,false) end); eq(writes,0); eq(#saved,1)
end)
test('own lock requires explicit unlock',function()
  local ch=simple(); C.state.locks[0x1000]={}; errors(function() C.transaction('own lock',ch,nil,false) end); eq(writes,0)
end)
test('PID change rejects old addresses and clears locks',function()
  local ch=simple(); C.state.locks[0x1000]={}; target.pid=101
  errors(function() C.transaction('stale process',ch,nil,false) end); eq(writes,0); eq(next(C.state.locks),nil)
end)
test('same PID but different package is rejected',function()
  local ch=simple(); target.packageName='another.app'
  errors(function() C.transaction('wrong target',ch,nil,false) end); eq(writes,0)
end)
test('undo refuses game-changed values',function()
  local ch=simple(); C.transaction('test',ch,nil,false); mem[0x1000]=99; local before=writes
  errors(C.undo); eq(writes,before); eq(#C.state.history,1)
end)
test('duplicate transaction address rejects',function()
  mem[0x1000]=5; errors(function() C.transaction('duplicate',{{address=0x1000,value=1},{address=0x1000,value=2}},nil,false) end); eq(writes,0)
end)
test('skill replacement writes TARGET flag and supports undo',function()
  put(0x1000,{{0,1061},{4,1062}}); put(0x2000,{{0,1071},{4,1072},{0x4C,0}})
  local a=C.unique(C.search(1061,{{0,1061},{4,1062}})); local b=C.unique(C.search(1071,{{0,1071},{4,1072}}))
  C.transaction('skill',{{address=a,value=1071},{address=b+0x4C,value=1}},{{address=a+4,value=1062},{address=b+4,value=1072}},false)
  eq(mem[0x1000],1071); eq(mem[0x204C],1); C.undo(); eq(mem[0x1000],1061); eq(mem[0x204C],0)
end)
test('all gift markers restore before final inventory write',function()
  local old,new={},{}
  for i=1,3 do local a=0x1000+i*16; mem[a]=0; old[i]={address=a,value=0}; new[i]={address=a,value=i} end
  C.transaction('markers',new,old,false,false)
  C.state.probe={old=old,new=new,key=C.state.key,epoch=C.state.epoch}
  C.restoreProbe(); eq(C.state.probe,nil); for _,p in ipairs(old) do eq(mem[p.address],0) end
  eq(#C.state.history,0)
end)
test('changed gift markers never blindly overwrite',function()
  mem[0x1000]=88
  C.state.probe={old={{address=0x1000,value=0}},new={{address=0x1000,value=1}},key=C.state.key,epoch=C.state.epoch}
  errors(C.restoreProbe); eq(mem[0x1000],88); assert(C.state.probe); eq(writes,0)
end)
test('gift restoration cannot cross PID',function()
  mem[0x1000]=1
  C.state.probe={old={{address=0x1000,value=0}},new={{address=0x1000,value=1}},key=C.state.key,epoch=C.state.epoch}
  target.pid=999; errors(C.restoreProbe); eq(writes,0)
end)
test('lock updates value then stops on guard change',function()
  mem[0x1000]=7; mem[0x1004]=100
  C.state.locks[0x1000]={address=0x1000,value=10,guards={{address=0x1004,value=100}},key=C.state.key}
  C.tick(); eq(mem[0x1000],10); mem[0x1004]=101; local before=writes
  C.tick(); eq(C.state.locks[0x1000],nil); eq(writes,before)
end)
test('panel cannot exceed six stars',function() errors(function() C.panelSpec(1001,{7,0,0,0,0,0}) end) end)
test('integer-safe pagination keeps final partial page',function()
  for _,p in ipairs({{0,0},{1,1},{24,1},{25,1},{26,2},{136,6},{680,28}}) do eq(C.pageCount(p[1],25),p[2]) end
  errors(function() C.pageCount(1,0) end)
end)
test('pagination formula tolerates GG truncated division',function()
  for n=0,1000 do
    local ggQuotient=math.floor((n+24)/25)
    eq(C.pageCount(n,25),ggQuotient)
    eq(ggQuotient,math.ceil(n/25)) -- Stock Lua reference, not GG arithmetic.
  end
end)
test('target switch during read invalidates batch',function()
  mem[0x1000]=7; afterRead=function() target.pid=101 end
  errors(function() C.read({0x1000}) end); eq(writes,0)
end)
test('target switch after write prevents rollback into new process',function()
  local ch=simple()
  afterWrite=function() target.pid=101; mem={[0x1000]=777,[0x1004]=888} end
  errors(function() C.transaction('switch',ch,nil,false) end)
  eq(writes,1); eq(mem[0x1000],777); eq(mem[0x1004],888); assert(C.state.pending); eq(calls.resumes,nil)
end)
test('deferred recovery rejects unexpected intervening value',function()
  local ch=simple(); failAlways=true; errors(function() C.transaction('pending',ch,nil,false) end)
  failAlways=false; mem[0x1000]=999; local before=writes
  errors(C.recover); eq(writes,before); eq(mem[0x1000],999); assert(C.state.pending)
end)
test('target info missing PID fails closed',function()
  target.pid=nil; errors(C.bind); eq(writes,0)
end)
test('unaligned address fails before GG write',function()
  mem[0x1001]=5; errors(function() C.transaction('unaligned',{{address=0x1001,value=7}},nil,false) end); eq(writes,0)
end)
test('numeric float integer accepted without tostring dependency',function()
  eq(C.integer(3.0,0,6),3); errors(function() C.integer(3.5,0,6) end)
  errors(function() C.integer(0/0) end); errors(function() C.integer(math.huge) end)
end)
print(string.format('\nRESULT: %d passed, %d failed (mock API only; %s)',passed,failed,_VERSION))
assert(failed==0,'Tests failed')
