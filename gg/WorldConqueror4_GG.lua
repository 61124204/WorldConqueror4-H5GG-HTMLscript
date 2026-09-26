-- World Conqueror 4 / GameGuardian experimental data-layout port, v0.1.0
-- Source: 61124204/WorldConqueror4-H5GG-HTMLscript
-- Source commit: 08b60e144ea30baca569f73fba82b813695f43c6
-- index.html blob: 97fe98ad0c919d0fabbb3d9ef2d327f6e06c83b9
-- Lua 5.2-compatible syntax. No remote code, HTTP, payment or login operations.
-- WARNING: H5GG offsets are hypotheses on Android, NOT device-verified offsets.
-- Back up saves. Use only your own offline game. Reset after every scene change.
local C = {VERSION='0.1.0', SOURCE='08b60e144ea30baca569f73fba82b813695f43c6'}
local G = gg
local U32, I32MAX = 4294967296, 2147483647
C.profile = {
  key=518867, resource={0,4,8}, faction=-0x84, color=0x94, control=0x98,
  panel={0x54,0x58,0x5C,0x60,0x64,0x68}, generalInitial=0x68,
  slots={0xB0,0xB4}, skillFlag=0x4C, medalStep=0x20,
  unit={0,4,8,0x1C,0x20,0x38,0x3C,0x50}
}
local S = {history={}, locks={}, catalogs={}, epoch=0, maxResults=200000, batch=256}
C.state=S
local order={'march','infantry','armor','artillery','navy','airForce'}
local stars={'行军','步兵','坦克','炮兵','海军','空军'}
local unitNames={'当前生命','生命上限','当前移动力','士气持续时间','士气状态','技能持续时间','技能冷却时间','攻击状态'}
local function fail(s) error(tostring(s),0) end
local function trim(s) return tostring(s or ''):match('^%s*(.-)%s*$') end
function C.integer(s,lo,hi)
  local t=trim(s)
  if type(s)~='number' and not t:match('^[+-]?%d+$') then fail('需要整数，不能留空：'..t) end
  local n=type(s)=='number' and s or tonumber(t)
  if not n or n~=n or n%1~=0 or n<(lo or -2147483648) or n>(hi or I32MAX) then fail('整数超出范围：'..t) end
  return n
end
function C.signed(n) n=n%U32; if n>=2147483648 then n=n-U32 end; return n end
function C.xor(a,b)
  a,b=a%U32,b%U32
  local r,p=0,1
  for _=1,32 do
    local x,y=a%2,b%2
    if x~=y then r=r+p end
    a,b,p=math.floor(a/2),math.floor(b/2),p*2
  end
  return C.signed(r)
end
function C.encode(n) return C.xor(n,C.profile.key) end
function C.color(hex)
  hex=trim(hex)
  if not hex:match('^#%x%x%x%x%x%x$') then fail('颜色格式必须为 #RRGGBB') end
  local r,g,b=tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)
  return C.signed(4278190080+b*65536+g*256+r)
end
function C.colorText(v)
  v=v%U32
  return string.format('#%02X%02X%02X',v%256,math.floor(v/256)%256,math.floor(v/65536)%256)
end
local function address(a)
  if type(a)~='number' or a<0 or a>9007199254740991 or a%1~=0 or a%4~=0 then fail('无效或非 DWORD 对齐地址') end
  return a
end
local function hex(a) return string.format('0x%X',address(a)) end
local function result(r,context)
  if type(r)=='string' or r==false then fail(context..'：'..tostring(r)) end
  return r
end
local function infoKey(t)
  if type(t)~='table' or not tonumber(t.pid) or not t.packageName then fail('请先在 GG 中选择游戏进程；需要有效 PID 和包名。') end
  return tostring(t.pid)..'|'..t.packageName..'|'..tostring(t.versionCode)..'|'..tostring(t.x64)
end
function C.bind()
  local t=G.getTargetInfo()
  S.key=infoKey(t); S.info=t; S.epoch=S.epoch+1
  S.history={}; S.locks={}; S.pending=nil; S.probe=nil
end
function C.check()
  if infoKey(G.getTargetInfo())~=S.key then
    S.locks={}
    fail('进程已切换或重启；已停止本脚本锁定。旧地址禁止写入。请退出并重跑脚本。')
  end
end
function C.read(addrs)
  C.check()
  local out={}
  for start=1,#addrs,S.batch do
    local q={}
    for i=start,math.min(start+S.batch-1,#addrs) do q[#q+1]={address=address(addrs[i]),flags=G.TYPE_DWORD} end
    local r=G.getValues(q)
    if type(r)~='table' or #r~=#q then fail('内存读取失败；停止本次定位，不能把未读候选当作不匹配。') end
    for j,v in ipairs(r) do
      local n=tonumber(v.value)
      if v.address~=q[j].address or not n or n%1~=0 then fail('GG 返回了无效内存数据') end
      out[#out+1]=C.signed(n)
    end
  end
  return out
end
function C.filter(pool,spec)
  local rows=pool
  for _,p in ipairs(spec) do
    local q,keep={},{}
    for _,a in ipairs(rows) do q[#q+1]=address(a+p[1]) end
    local vals=C.read(q)
    for i,a in ipairs(rows) do if vals[i]==C.signed(p[2]) then keep[#keep+1]=a end end
    rows=keep
    if #rows==0 then break end
  end
  return rows
end
function C.search(value,spec)
  C.check(); G.clearResults()
  result(G.searchNumber(tostring(C.signed(value)),G.TYPE_DWORD,false,G.SIGN_EQUAL,0,-1),'搜索失败')
  local n=tonumber(G.getResultsCount())
  if not n or n<0 or n>S.maxResults then fail('候选过多（'..tostring(n)..'），本次完全中止；请缩小内存区域或改用更有区分度的值。') end
  local out,seen={},{}
  for skip=0,n-1,S.batch do
    C.check()
    local take=math.min(S.batch,n-skip)
    local r=G.getResults(take,skip)
    if type(r)~='table' or #r~=take then fail('候选分页不完整；拒绝基于截断结果写入。') end
    local pool={}
    for _,v in ipairs(r) do
      local a=address(v.address)
      if seen[a] then fail('GG 候选分页出现重复；请更新 GG 后重试。') end
      seen[a]=true; pool[#pool+1]=a
    end
    for _,a in ipairs(C.filter(pool,spec or {{0,value}})) do out[#out+1]=a end
  end
  S.lastSearch={initial=n,matches=#out}
  G.clearResults()
  return out
end
function C.unique(pool)
  if #pool~=1 then fail('完整核验后有 '..#pool..' 个匹配，未写入。请核对当前数值、资料版本、内存区域及 Android 偏移。') end
  return pool[1]
end
function C.guards(base,spec)
  local g={}
  for _,p in ipairs(spec) do g[#g+1]={address=base+p[1],value=C.signed(p[2])} end
  return g
end
local function verifyGuards(guards)
  local q={}; for _,p in ipairs(guards or {}) do q[#q+1]=p.address end
  local vals=C.read(q)
  for i,p in ipairs(guards or {}) do if vals[i]~=C.signed(p.value) then fail('定位条件已变化：'..hex(p.address)..'。请重新定位。') end end
end
local function withPause(fn)
  C.check()
  local was=G.isProcessPaused()
  if not was then
    result(G.processPause(),'暂停进程失败')
    if not G.isProcessPaused() then fail('进程未暂停，取消写入。') end
  end
  local ok,v=xpcall(fn,function(e) return tostring(e) end)
  -- Never resume a different process, or one the user paused before this action.
  local same,k=pcall(function() return infoKey(G.getTargetInfo()) end)
  if not was and same and k==S.key then
    local rok=pcall(function() result(G.processResume(),'恢复进程失败') end)
    if not rok or G.isProcessPaused() then
      G.alert('游戏可能仍处于暂停状态。请在 GG 中手动恢复进程。')
    end
  end
  if not ok then fail(v) end
  return v
end
local function setAndVerify(items)
  local q,w={},{}
  for i,p in ipairs(items) do
    q[i]=address(p.address)
    w[i]={address=p.address,flags=G.TYPE_DWORD,value=tostring(C.signed(p.value))}
  end
  result(G.setValues(w),'写入失败')
  local vals=C.read(q)
  for i,p in ipairs(items) do if vals[i]~=C.signed(p.value) then fail('写入回读不一致：'..hex(p.address)) end end
end
local function noForeignFreeze(changes)
  if type(G.getListItems)~='function' then return end
  local saved=G.getListItems()
  if type(saved)~='table' then fail('无法检查 GG 保存列表的冻结状态') end
  local sizes={[G.TYPE_BYTE]=1,[G.TYPE_WORD]=2,[G.TYPE_DWORD]=4,[G.TYPE_QWORD]=8,[G.TYPE_FLOAT]=4,[G.TYPE_DOUBLE]=8}
  for _,v in ipairs(saved) do
    if v.freeze then
      local size=sizes[v.flags] or 8
      for _,p in ipairs(changes) do
        if v.address<p.address+4 and p.address<v.address+size then fail('目标与 GG 已有冻结项重叠。请先手动解除该冻结项。') end
      end
    end
  end
end
function C.transaction(label,changes,guards,confirm,record)
  C.check()
  if S.pending then fail('上次回滚尚未完成，请先使用“恢复未完成写入”。') end
  if #changes==0 then fail('没有写入目标') end
  local q,old,seen={}, {},{}
  for i,p in ipairs(changes) do
    address(p.address); C.integer(p.value,-2147483648,I32MAX)
    if seen[p.address] then fail('同一次事务包含重复地址') end
    if S.locks[p.address] then fail('请先解除本脚本对此地址的锁定') end
    seen[p.address]=true; q[i]=p.address
  end
  verifyGuards(guards); noForeignFreeze(changes)
  local vals=C.read(q)
  for i,p in ipairs(changes) do old[i]={address=p.address,value=vals[i]} end
  if confirm~=false then
    local lines={label,'Android 偏移尚未真机验证。请确认以下目标：'}
    for i,p in ipairs(changes) do if i<=8 then lines[#lines+1]=hex(p.address)..'  '..old[i].value..' → '..p.value end end
    if #changes>8 then lines[#lines+1]='共 '..#changes..' 个 DWORD' end
    if G.alert(table.concat(lines,'\n'),'写入','取消')~=1 then return false end
  end
  local entry={label=label,key=S.key,epoch=S.epoch,old=old,new=changes,time=os.date('%Y-%m-%d %H:%M:%S')}
  withPause(function()
    verifyGuards(guards); verifyGuards(old); noForeignFreeze(changes)
    S.pending=entry
    local ok,err=pcall(setAndVerify,changes)
    if not ok then
      local restored,rerr=pcall(setAndVerify,old)
      if restored then S.pending=nil else S.locks={} end
      fail(tostring(err)..(restored and '\n已回读确认恢复写入前的数值。' or '\n回滚失败：'..tostring(rerr)..'\n已停用锁定并保留恢复记录。'))
    end
    S.pending=nil
  end)
  if record~=false then S.history[#S.history+1]=entry end
  return true
end
function C.recover()
  local p=S.pending
  if not p then return end
  C.check()
  if p.key~=S.key or p.epoch~=S.epoch then fail('恢复记录不属于当前会话') end
  withPause(function() noForeignFreeze(p.old); setAndVerify(p.old) end)
  S.pending=nil
end
function C.undo()
  local p=S.history[#S.history]
  if not p then fail('本会话没有可撤销记录') end
  C.check()
  if p.key~=S.key or p.epoch~=S.epoch then fail('旧会话记录禁止恢复') end
  -- LIFO + compare-before-restore. Natural game changes also cause refusal.
  if C.transaction('撤销：'..p.label,p.old,p.new,true,false) then table.remove(S.history) end
end
function C.panelSpec(id,values)
  local spec={{0,id}}
  for i,v in ipairs(values) do spec[#spec+1]={C.profile.panel[i],C.integer(v,0,6)} end
  if #values~=6 then fail('面板必须包含六项') end
  return spec
end
function C.slotSpec(g)
  local spec={{0,C.integer(g.id,1,I32MAX)}}
  for k,kind in ipairs({'initial','maximum'}) do
    if type(g[kind])~='table' then fail('将领缺少初始/上限资料') end
    for i,key in ipairs(order) do spec[#spec+1]={C.profile.generalInitial+((k-1)*6+i-1)*4,C.integer(g[kind][key],0,6)} end
  end
  return spec
end
function C.resourceSpec(v)
  local spec={}
  for i=1,3 do spec[i]={C.profile.resource[i],C.encode(C.integer(v[i],0,999999))} end
  return spec
end
-- A small strict JSON reader. Data are never passed to load/loadstring/dofile.
function C.json(text)
  if type(text)~='string' or #text>2097152 then fail('JSON 无效或超过 2 MiB') end
  text=text:gsub('^\239\187\191','')
  local i,len=1,#text
  local function bad() fail('JSON 格式错误，字节 '..i) end
  local function ws() while text:sub(i,i):match('%s') and i<=len do i=i+1 end end
  local function utf(n)
    if n<128 then return string.char(n) end
    if n<2048 then return string.char(192+math.floor(n/64),128+n%64) end
    if n<65536 then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
    return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64)
  end
  local function code()
    local s=text:sub(i,i+3)
    if #s~=4 or not s:match('^%x%x%x%x$') then bad() end
    i=i+4; return tonumber(s,16)
  end
  local function str()
    if text:sub(i,i)~='"' then bad() end
    i=i+1; local out={}
    while i<=len do
      local c=text:sub(i,i); i=i+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        c=text:sub(i,i); i=i+1
        local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if c=='u' then
          local n=code()
          if n>=55296 and n<=56319 then
            if text:sub(i,i+1)~='\\u' then bad() end
            i=i+2; local low=code()
            if low<56320 or low>57343 then bad() end
            n=65536+(n-55296)*1024+low-56320
          elseif n>=56320 and n<=57343 then bad() end
          out[#out+1]=utf(n)
        elseif escapes[c] then out[#out+1]=escapes[c] else bad() end
      else
        if c:byte()<32 then bad() end
        out[#out+1]=c
      end
    end
    bad()
  end
  local parse
  parse=function(depth)
    if depth>64 then bad() end
    ws(); local c=text:sub(i,i)
    if c=='"' then return str() end
    if c=='{' or c=='[' then
      local obj,close={},c=='{' and '}' or ']'; i=i+1; ws()
      if text:sub(i,i)==close then i=i+1; return obj end
      while true do
        ws(); local key
        if c=='{' then key=str(); ws(); if text:sub(i,i)~=':' then bad() end; i=i+1 end
        local v=parse(depth+1)
        if c=='{' then if obj[key]~=nil then bad() end; obj[key]=v else obj[#obj+1]=v end
        ws(); local d=text:sub(i,i); i=i+1
        if d==close then return obj end
        if d~=',' then bad() end
      end
    end
    if text:sub(i,i+3)=='true' then i=i+4; return true end
    if text:sub(i,i+4)=='false' then i=i+5; return false end
    if text:sub(i,i+3)=='null' then i=i+4; return C.JSON_NULL end
    local start=i
    if c=='-' then i=i+1 end
    c=text:sub(i,i)
    if c=='0' then i=i+1
    elseif c:match('[1-9]') then repeat i=i+1 until not text:sub(i,i):match('%d')
    else bad() end
    if text:sub(i,i)=='.' then
      i=i+1; if not text:sub(i,i):match('%d') then bad() end
      repeat i=i+1 until not text:sub(i,i):match('%d')
    end
    c=text:sub(i,i)
    if c=='e' or c=='E' then
      i=i+1; c=text:sub(i,i); if c=='+' or c=='-' then i=i+1 end
      if not text:sub(i,i):match('%d') then bad() end
      repeat i=i+1 until not text:sub(i,i):match('%d')
    end
    local n=tonumber(text:sub(start,i-1))
    if not n or n~=n or n==math.huge or n==-math.huge then bad() end
    return n
  end
  local value=parse(0); ws(); if i<=len then bad() end; return value
end
C.JSON_NULL={}
local function notify(s) G.alert(tostring(s)) end
local function ask(labels,defaults,limits)
  local kinds={}; for i=1,#labels do kinds[i]='text' end
  local r=G.prompt(labels,defaults or {},kinds)
  if not r then return nil end
  local v={}
  for i,s in ipairs(r) do
    if limits then v[i]=C.integer(s,limits[i][1],limits[i][2]) else v[i]=trim(s) end
  end
  return v
end
local function numbers(labels,defaults,lo,hi)
  local lim={}; for i=1,#labels do lim[i]={lo,hi} end
  return ask(labels,defaults,lim)
end
local function baseDir()
  return (G.getFile() or ''):match('^(.*[/\\])') or './'
end
local catalogPaths={generals='generals/generals-type1.json',skills='skills/skills.json',stages='stages/initial-countries.json'}
function C.catalog(kind)
  if S.catalogs[kind] then return S.catalogs[kind] end
  local path=catalogPaths[kind]; local name=path:match('([^/]+)$')
  local paths={baseDir()..'data/'..name,baseDir()..'../assets/'..path,baseDir()..'assets/'..path}
  for _,p in ipairs(paths) do
    local f=io.open(p,'rb')
    if f then
      local t=f:read(2097153); f:close()
      local data=C.json(t); local rows=data[kind] or data
      if type(rows)~='table' or #rows==0 then fail('资料为空：'..p) end
      S.catalogs[kind]=rows; return rows
    end
  end
  return nil
end
local function picker(rows,title,formatter)
  local text=ask({title..'：输入名称或 ID；留空显示全部'},{''})
  if not text then return nil end
  local terms={}; for w in text[1]:lower():gmatch('%S+') do terms[#terms+1]=w end
  local filtered={}
  for _,r in ipairs(rows) do
    local line=formatter(r); local hay=(line..' '..tostring(r.englishName or '')):lower(); local yes=true
    for _,w in ipairs(terms) do if not hay:find(w,1,true) then yes=false end end
    if yes then filtered[#filtered+1]={row=r,line=line} end
  end
  if #filtered==0 then fail('没有匹配的资料') end
  local page=1
  while true do
    local labels,keys={},{}
    for i=(page-1)*25+1,math.min(page*25,#filtered) do labels[#labels+1]=filtered[i].line; keys[#keys+1]=i end
    local prev=#labels+1; labels[prev]='上一页'
    local nextp=#labels+1; labels[nextp]='下一页'
    local c=G.choice(labels,nil,title..' '..page..'/'..math.ceil(#filtered/25))
    if not c then return nil end
    if c==prev then page=math.max(1,page-1)
    elseif c==nextp then page=math.min(math.ceil(#filtered/25),page+1)
    else return filtered[keys[c]].row end
  end
end
local function general(title)
  local rows=C.catalog('generals')
  if rows then return picker(rows,title,function(r) return r.name..' ['..r.id..']' end) end
  local r=numbers({title..' ID（缺少 JSON，使用手动模式）'},{''},1,I32MAX)
  if r then return {id=r[1],name='ID '..r[1]} end
end
local function waitForGame(message)
  notify(message..'\n返回游戏操作；完成后点击 GG 悬浮按钮继续。不要换局或切换进程。')
  G.setVisible(false)
  while not G.isVisible() do C.check(); G.sleep(150) end
  G.setVisible(false); C.check()
end
local function refineLoop(pool,getValues,buildSpec,title)
  while #pool>1 do
    local c=G.choice({'返回游戏改变数值后再次过滤','取消'},nil,title..'：'..#pool..' 个候选，尚未写入')
    if c~=1 then return nil,nil end
    waitForGame('请只改变目标对象的数值。')
    local vals=getValues(); if not vals then return nil,nil end
    local spec=buildSpec(vals); pool=C.filter(pool,spec)
    if #pool==1 then return pool[1],spec end
  end
  return C.unique(pool),nil
end
local function snapshot(base,offsets)
  local q,g={},{}
  for _,off in ipairs(offsets) do q[#q+1]=base+off end
  local vals=C.read(q)
  for i,a in ipairs(q) do g[#g+1]={address=a,value=vals[i]} end
  return vals,g
end
local function writeFields(label,base,offsets,vals,guards)
  local changes={}
  for i,v in ipairs(vals) do changes[i]={address=base+offsets[i],value=C.signed(v)} end
  if C.transaction(label,changes,guards) then G.toast('写入及回读完成') end
end
local function editResource(base,spec)
  verifyGuards(C.guards(base,spec))
  while true do
    local raw,guards=snapshot(base,C.profile.resource)
    local decoded={C.encode(raw[1]),C.encode(raw[2]),C.encode(raw[3])}
    for _,v in ipairs(decoded) do C.integer(v,0,999999) end
    local c=G.choice({'修改三项资源','修改阵营 0–6','修改玩家可控 0/1','修改国家颜色 #RRGGBB','返回'},nil,
      hex(base)..'\n经济 '..decoded[1]..' / 工业 '..decoded[2]..' / 科技 '..decoded[3])
    if not c or c==5 then return end
    if c==1 then
      local v=numbers({'经济 0–999999','工业 0–999999','科技 0–999999'},decoded,0,999999)
      if v then for i=1,3 do v[i]=C.encode(v[i]) end; writeFields('三项资源',base,C.profile.resource,v,guards) end
    elseif c==2 or c==3 then
      local off=c==2 and C.profile.faction or C.profile.control; local max=c==2 and 6 or 1
      local cur=C.read({base+off})[1]; C.integer(cur,0,max)
      local v=numbers({c==2 and '新阵营 0–6' or '玩家可控 0/1'},{cur},0,max)
      if v then guards[#guards+1]={address=base+off,value=cur}; writeFields('国家标志',base,{off},v,guards) end
    else
      local cur=C.read({base+C.profile.color})[1]
      if math.floor((cur%U32)/16777216)~=255 then fail('颜色 alpha 字节不是 FF，布局不匹配；未写入') end
      local v=ask({'国家颜色 #RRGGBB'},{C.colorText(cur)})
      if v then guards[#guards+1]={address=base+C.profile.color,value=cur}; writeFields('国家颜色',base,{C.profile.color},{C.color(v[1])},guards) end
    end
  end
end
local function resource()
  local mode=G.choice({'经济单项搜索（变化后过滤）','三项资源联合搜索','初始国家资料搜索'},nil,'资源修改')
  if not mode then return end
  local vals,spec,pool
  if mode==3 then
    local stages=C.catalog('stages')
    if not stages then fail('缺少 initial-countries.json，请下载分支的完整 ZIP 并解压。') end
    local stage=picker(stages,'选择剧本',function(r) return r.name..' ['..r.id..']' end); if not stage then return end
    local country=picker(stage.countries,'选择国家',function(r) return r.name..' / 行动 '..r.sequence..' / '..r.color end)
    if not country then return end
    vals={country.economy,country.industry,country.technology}; spec=C.resourceSpec(vals)
    spec[#spec+1]={C.profile.color,C.color(country.color)}
    -- Unlike the H5 source, never silently fall back when color does not match.
    pool=C.search(C.encode(vals[1]),spec)
    return editResource(C.unique(pool),spec)
  end
  local labels=mode==1 and {'当前经济'} or {'当前经济','当前工业','当前科技'}
  local function input() return numbers(labels,{},0,999999) end
  local function make(v) return mode==1 and {{0,C.encode(v[1])}} or C.resourceSpec(v) end
  vals=input(); if not vals then return end
  spec=make(vals); pool=C.search(C.encode(vals[1]),spec)
  local base,newSpec=refineLoop(pool,input,make,'资源定位')
  if base then editResource(base,newSpec or spec) end
end
local function panel(replace)
  local g=general('选择原将领'); if not g then return end
  local vals=numbers(stars,{},0,6); if not vals then return end
  local spec=C.panelSpec(g.id,vals); local base=C.unique(C.search(g.id,spec))
  if replace then
    local dest=general('选择目标将领'); if not dest then return end
    writeFields('将领替换 '..g.name..' → '..dest.name,base,{0},{dest.id},C.guards(base,spec))
  else
    local v=numbers(stars,vals,0,6)
    if v then writeFields('六维面板 '..g.name,base,C.profile.panel,v,C.guards(base,spec)) end
  end
end
local function slots()
  local g=general('技能槽：选择将领'); if not g then return end
  if not g.initial or not g.maximum then
    g.initial={}; g.maximum={}
    for _,kind in ipairs({'initial','maximum'}) do
      local label={}; for i,s in ipairs(stars) do label[i]=(kind=='initial' and '资料初始 ' or '资料上限 ')..s end
      local v=numbers(label,{},0,6); if not v then return end
      for i,k in ipairs(order) do g[kind][k]=v[i] end
    end
  end
  local spec=C.slotSpec(g); local base=C.unique(C.search(g.id,spec))
  local cur=C.read({base+C.profile.slots[1],base+C.profile.slots[2]})
  for _,v in ipairs(cur) do C.integer(v,0,5) end
  local guards=C.guards(base,spec)
  for i,off in ipairs(C.profile.slots) do guards[#guards+1]={address=base+off,value=cur[i]} end
  writeFields('技能槽双 5 '..g.name,base,C.profile.slots,{5,5},guards)
end
local function skill(title)
  local rows=C.catalog('skills')
  if rows then
    local list={}
    for _,r in ipairs(rows) do
      if tonumber(r.level)==1 then
        for _,n in ipairs(rows) do
          if n.name==r.name and n.type==r.type and tonumber(n.level)==2 then
            list[#list+1]={id=r.id,next=n.id,name=r.name}; break
          end
        end
      end
    end
    return picker(list,title,function(r) return r.name..' ['..r.id..';'..r.next..']' end)
  end
  local v=numbers({title..' Lv1 ID','同技能 Lv2 ID（不能假设为 ID+1）'},{},1,I32MAX)
  if v then return {id=v[1],next=v[2],name=tostring(v[1])} end
end
local function skills()
  local from=skill('原技能'); if not from then return end
  local fs={{0,from.id},{4,from.next}}; local a=C.unique(C.search(from.id,fs))
  local dest=skill('新技能'); if not dest then return end
  if dest.id==from.id then fail('原技能与目标技能相同') end
  local ds={{0,dest.id},{4,dest.next}}; local b=C.unique(C.search(dest.id,ds))
  local flag=b+C.profile.skillFlag; local current=C.read({flag})[1]; C.integer(current,0,1)
  local guards=C.guards(a,fs)
  for _,g in ipairs(C.guards(b,ds)) do guards[#guards+1]=g end
  guards[#guards+1]={address=flag,value=current}
  C.transaction('技能替换 '..from.name..' → '..dest.name,{{address=a,value=dest.id},{address=flag,value=1}},guards)
end
local function medals()
  local spec={{0,100},{4,37500}}; local base=C.unique(C.search(100,spec)); local changes={}
  for i=0,4 do changes[#changes+1]={address=base+i*C.profile.medalStep,value=-2000} end
  C.transaction('原版勋章规则：5 个间隔 0x20 的值写为 -2000；这不是直接设置勋章余额',changes,C.guards(base,spec))
end
function C.restoreProbe()
  local p=S.probe
  if not p then return end
  C.check()
  if p.key~=S.key or p.epoch~=S.epoch then fail('礼包标记不属于当前会话') end
  -- Refuse to overwrite values changed by the game while the markers were live.
  if C.transaction('还原礼包临时标记',p.old,p.new,false,false) then S.probe=nil end
end
local function gifts()
  local v=numbers({'当前进修礼包库存（未出现时填 0）'},{0},0,I32MAX); if not v then return end
  local spec={{0,300},{4,0},{8,0},{12,v[1]}}; local pool=C.search(300,spec)
  if #pool==0 then fail('未找到礼包结构') end
  local base
  if #pool==1 then base=pool[1]
  else
    if #pool>64 then fail('礼包匹配超过 64 个，禁止批量临时标记。请核对布局。') end
    if G.alert('共有 '..#pool..' 个礼包候选。可暂时把候选库存写成 1、2、3…，观察显示值后全部恢复。\n期间不得领取、购买、消耗、存档、换局或强制停止脚本。候选未必都是礼包，标记有风险。','临时标记','取消')~=1 then return end
    local changes,old,guards={},{},{}
    for i,a in ipairs(pool) do
      changes[i]={address=a+12,value=i}; old[i]={address=a+12,value=v[1]}
      for _,g in ipairs(C.guards(a,spec)) do guards[#guards+1]=g end
    end
    if not C.transaction('礼包候选临时标记',changes,guards,false,false) then return end
    S.probe={old=old,new=changes,key=S.key,epoch=S.epoch}
    local chosen
    local ok,err=xpcall(function()
      waitForGame('重新打开礼包界面，只观察库存标记，不进行任何领取或保存。')
      local t=numbers({'界面显示的库存标记 1–'..#pool..'；取消会还原'},{},1,#pool)
      if t then chosen=t[1] end
    end,function(e) return tostring(e) end)
    C.restoreProbe()
    if not ok then fail(err) end
    if not chosen then return end
    base=pool[chosen]
  end
  local target=numbers({'目标礼包库存'},{99},0,I32MAX); if not target then return end
  writeFields('进修礼包库存',base,{12},target,C.guards(base,spec))
end
local function validUnit(v)
  C.integer(v[1],0,I32MAX); C.integer(v[2],1,I32MAX)
  if v[1]>v[2] then fail('当前生命大于生命上限，单位布局校验失败') end
  C.integer(v[5],-3,1); C.integer(v[8],0,1)
end
local function unit()
  local function input()
    local v=numbers({'当前生命值','生命上限（不是当前生命值）'},{},0,I32MAX)
    if v and (v[2]<1 or v[1]>v[2]) then fail('生命范围不合理') end
    return v
  end
  local function spec(v) return {{0,v[1]},{4,v[2]}} end
  local v=input(); if not v then return end
  local sp=spec(v); local base,nextSpec=refineLoop(C.search(v[1],sp),input,spec,'单位生命定位')
  if not base then return end
  verifyGuards(C.guards(base,nextSpec or sp))
  while true do
    local vals,guards=snapshot(base,C.profile.unit); validUnit(vals)
    local labels={}
    for i,n in ipairs(unitNames) do labels[i]=n..' = '..vals[i]..(S.locks[base+C.profile.unit[i]] and ' [锁定]' or '') end
    labels[9]='返回'
    local c=G.choice(labels,nil,'单位 '..hex(base)..'\n换局/单位消失后必须重置会话')
    if not c or c==9 then return end
    local a=base+C.profile.unit[c]
    if S.locks[a] then S.locks[a]=nil; G.toast('已解除此属性锁定')
    else
      local lo,hi=-2147483648,I32MAX
      if c==1 then lo,hi=0,vals[2] elseif c==2 then lo=math.max(1,vals[1]) elseif c==5 then lo,hi=-3,1 elseif c==8 then lo,hi=0,1 end
      local t=numbers({unitNames[c]..' ['..lo..'..'..hi..']'}, {vals[c]},lo,hi)
      if t and C.transaction(unitNames[c],{{address=a,value=t[1]}},guards) then
        if G.alert('是否在本脚本空闲循环中保持该数值？\n对话框打开时暂停锁定；其他单位字段变化会停止锁定。强制结束脚本也会停止。','保持','不保持')==1 then
          local lockGuards={}
          for _,g in ipairs(guards) do if g.address~=a then lockGuards[#lockGuards+1]=g end end
          S.locks[a]={address=a,value=t[1],guards=lockGuards,key=S.key}
        end
      end
    end
  end
end
function C.tick()
  C.check()
  if S.pending or S.probe then return end
  for a,l in pairs(S.locks) do
    local ok=pcall(function()
      verifyGuards(l.guards); noForeignFreeze({l})
      withPause(function() verifyGuards(l.guards); setAndVerify({l}) end)
    end)
    if not ok then S.locks[a]=nil; G.toast('字段/进程变化或读取失败，已停止一项锁定') end
  end
end
local function chooseRanges()
  if S.probe or S.pending then fail('请先恢复未完成的写入/标记') end
  local choices={'匿名 A','C 分配 Ca','C BSS Cb','C 数据 Cd','Java 堆 Jh（扩展排查）'}
  local flags={G.REGION_ANONYMOUS,G.REGION_C_ALLOC,G.REGION_C_BSS,G.REGION_C_DATA,G.REGION_JAVA_HEAP}
  local picked=G.multiChoice(choices,{true,true,true,true,false},'搜索区域；默认不搜索可执行代码')
  if not picked then return end
  local mask=0; for i,f in ipairs(flags) do if picked[i] then mask=mask+f end end
  if mask==0 then fail('至少选择一个搜索区域') end
  result(G.setRanges(mask),'设置内存区域失败'); S.range=mask
end
local function exportLog()
  local path=baseDir()..'WC4_GG_diagnostics.txt'; local f,err=io.open(path,'w')
  if not f then fail('无法写入诊断文件：'..tostring(err)) end
  f:write('WC4 GG ',C.VERSION,'\nSource ',C.SOURCE,'\nSession ',tostring(S.key),'\nEpoch ',S.epoch,'\nRange ',tostring(S.range),'\nAndroid offsets: UNVERIFIED\n')
  if S.lastSearch then f:write('Search: ',S.lastSearch.initial,' -> ',S.lastSearch.matches,'\n') end
  local function log(p,status)
    f:write(status,' ',p.label,'\n')
    for i,v in ipairs(p.old) do f:write(hex(v.address),' ',v.value,' -> ',p.new[i].value,'\n') end
  end
  for _,p in ipairs(S.history) do log(p,'COMMITTED') end
  if S.pending then log(S.pending,'RECOVERY REQUIRED') end
  if S.probe then
    f:write('PROBE RESTORE REQUIRED\n')
    for i,v in ipairs(S.probe.old) do f:write(hex(v.address),' original=',v.value,' marker=',S.probe.new[i].value,'\n') end
  end
  f:close(); notify('诊断文件：'..path..'\n只记录进程信息、搜索计数和修改值；不会自动重新加载这些地址。')
end
local function runAction(fn)
  local ok,err=xpcall(fn,function(e) return tostring(e) end)
  if not ok then
    S.locks={}
    local restored,rerr=pcall(C.restoreProbe)
    notify('操作中止：'..err..(restored and '' or '\n礼包还原仍需处理：'..tostring(rerr)))
  end
end
local function mainMenu()
  local c=G.choice({'资源 / 国家 / 阵营','兵种属性 / 锁定','将领替换','面板六维星级','技能槽双 5','技能替换','贸易勋章原版规则','进修礼包库存','撤销最近一次修改','解除本脚本所有锁定','恢复未完成写入 / 礼包标记','搜索区域','导出诊断日志','换局后重置会话','一键通关（原版未实现）','退出'},nil,
    '世界征服者4 GG '..C.VERSION..' · Android 实验移植\n'..tostring(S.info.label or S.info.packageName)..' '..tostring(S.info.versionName)..' / '..(S.info.x64 and '64 位' or '32 位')..'\n取消菜单返回游戏；点击 GG 悬浮按钮唤出')
  if not c then return true end
  local actions={resource,unit,function() panel(true) end,function() panel(false) end,slots,skills,medals,gifts,C.undo,
    function() S.locks={}; G.toast('本脚本锁定已清除；未修改 GG 的保存列表') end,
    function() C.recover(); C.restoreProbe(); G.toast('恢复流程完成') end,
    chooseRanges,exportLog,
    function()
      if S.pending or S.probe then fail('恢复未完成；禁止丢弃记录') end
      if G.alert('换局后重置：停止锁定并丢弃当前会话撤销记录。已写入数值不会自动还原。','重置','取消')==1 then C.check(); C.bind() end
    end,
    function() notify('原 H5GG 脚本没有通关标识或写入逻辑。本移植版不猜测通关地址。') end}
  if c==16 then
    if S.pending then notify('存在未恢复写入。请先恢复或导出日志；游戏存档备份仍是最终恢复手段。'); return true end
    C.restoreProbe(); return false
  end
  if (S.pending or S.probe) and c~=10 and c~=11 and c~=13 then fail('存在待恢复写入或礼包标记，只能解除锁定、恢复或导出诊断。') end
  actions[c](); return true
end
function C.main()
  if type(G)~='table' then error('请在 Android GameGuardian 中运行此 Lua 文件。',0) end
  C.bind(); S.originalRange=G.getRanges()
  if G.alert('世界征服者4 GG 实验移植版\n\n当前进程：'..S.info.packageName..' (PID '..S.info.pid..')\n请确认这是你自己的离线游戏，并先备份存档。\n\n来源为 H5GG / iOS 结构，Android 偏移没有真机验证。数值与结构匹配不等于版本兼容保证。GG 搜索结果将被清空；不删除你的保存列表。\n\n禁止在标记期间领取/购买/存档；换局必须重置。','确认进程并继续','退出')~=1 then return end
  S.range=G.REGION_ANONYMOUS+G.REGION_C_ALLOC+G.REGION_C_BSS+G.REGION_C_DATA
  result(G.setRanges(S.range),'设置范围失败'); G.setVisible(false)
  local running,open=true,true
  while running do
    local alive,why=pcall(C.check)
    if not alive then notify(why..'\n旧会话存在的礼包标记/恢复记录不会写入新进程。'); break end
    if open or G.isVisible() then
      G.setVisible(false); open=false
      runAction(function() running=mainMenu() end)
    else runAction(C.tick) end
    if running then G.sleep(350) end
  end
  S.locks={}
  if S.originalRange then G.setRanges(S.originalRange) end
  G.setVisible(true)
end
if rawget(_G,'WC4_GG_TEST') then return C end
local ok,err=xpcall(C.main,function(e) return tostring(e) end)
if not ok and type(G)=='table' then
  S.locks={}
  pcall(C.restoreProbe)
  if S.originalRange then pcall(G.setRanges,S.originalRange) end
  G.alert('脚本停止：'..err..'\n请检查进程是否仍暂停；有未完成写入时不要保存游戏。')
elseif not ok then error(err,0) end
