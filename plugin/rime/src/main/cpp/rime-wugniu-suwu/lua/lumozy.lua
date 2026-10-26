-- lua/lumozy.lua —— 吳語拼音文輸入法（蘇滬混合腔羅馬字）核心組件
--
-- 由 wugniu_lumozy.schema.yaml 直接引用，弗需要在 rime.lua 裏向註冊：
--   lua_processor@*lumozy*case_processor   排在 speller 之前
--   lua_filter@*lumozy*romazy_filter       排在 simplifier 之後
--
-- 原理（學昭明語 romanization_input 个做法）：
--   方案照常走漢字詞典（wugniu_suwu），script_translator 个候選
--   TEXT 是漢字、COMMENT 是帶聲調个原始音節碼（spelling_hints）。
--   過濾器拿 COMMENT 按正字法折成拼音文，擔 TEXT 搭佢互換：
--   輸出＝拼音文，註釋＝漢字。聲調搭小撇全從原始碼即時計算。

local M = {}

-- ============ 大小寫記憶 ============
-- 用戶實際敲鍵个原大小寫串，搭 context.input 逐字對齊。
-- 祇有長度搭內容（小寫化後）完全吻合辰光纔好用於還原大小寫。
local orig_input = ''

local function orig_valid(inp)
  return #orig_input == #inp and orig_input:lower() == inp
end

-- 每趟按鍵前先對齊：回退鍵縮短就截斷（保留已知字形），
-- 前綴上屏等失聯就以小寫重建，之後新敲个字母繼續跟蹤。
local function resync(inp)
  if inp == '' then
    orig_input = ''
  elseif #orig_input >= #inp and orig_input:lower():sub(1, #inp) == inp then
    orig_input = orig_input:sub(1, #inp)
  else
    orig_input = inp
  end
end

-- ============ 蘇滬混合腔拼音文正字法 ============
-- 詞首音節按聲母搭聲調決定小撇（一律 U+0027）：
--   調 1                          → 詞前加 '   雞排 ci1ba2 → 'ciba
--   聲母 m/n/l/gn 配調 3/5/7      → 聲母後加 ' 美好 me3hau3 → m'ehau
--   成音節鼻音 m/n/ng 配陰調      → 音節前加 ' 嗯 n3 → 'n
--   其餘（調 2/4/6/8 等）         → 弗標       作興 tsoq7shin1 → tsoqshin
-- 輸出弗帶聲調數字，詞內音節連寫，詞搭詞之間用空格。

local YIN = { [1] = true, [3] = true, [5] = true, [7] = true }
local MLG = { m = true, n = true, l = true, gn = true }

local function first_syllable(body, tone)
  if body == 'm' or body == 'n' or body == 'ng' then
    if YIN[tone] then return "'" .. body end
    return body
  end
  if tone == 1 then
    return "'" .. body
  end
  if tone == 3 or tone == 5 or tone == 7 then
    local ini = body:match('^gn') or body:match('^ng')
      or body:match('^gh') or body:match('^[a-z]')
    if MLG[ini] then
      local rest = body:sub(#ini + 1)
      if rest == '' then return "'" .. body end
      return ini .. "'" .. rest
    end
  end
  return body
end

-- forms: 無調字母數組（一組＝一個詞），tone1: 該詞首音節聲調
local function word_from_forms(forms, tone1)
  if #forms == 0 then return nil end
  forms[1] = first_syllable(forms[1], tone1)
  return table.concat(forms)
end

-- ============ u 韻變體音節 ============
-- 詞典原碼（左）→ 變體（右）。敲變體同樣出字，輸出保留變體字形：
-- 地圖 di6du2 敲 didu 出 didu，敲 didou 出 didou。
-- 輸入匹配靠 schema 裏向 derive/u/ou/、derive/wu/ghou/（基底方案自帶）。
local VARIANT = {
  wu = 'ghou', u = 'ou',
  tu = 'tou', thu = 'thou', du = 'dou',
  nu = 'nou', lu = 'lou',
  ku = 'kou', khu = 'khou', gu = 'gou', ngu = 'ngou', hu = 'hou',
  tsu = 'tsou', tshu = 'tshou', su = 'sou', zu = 'zou',
}

-- 拿敲入字母串 t 逐音節匹配：每只音節吃掉原式或者變體式个字母。
-- 成功返回逐音節採用式个數組；弗落返回 nil（輸出退回原式）。
local function match_variant(bare, t)
  local n = #bare
  local chosen = {}
  local function walk(i, pos)
    if i > n then return pos == #t + 1 end
    local s = bare[i]
    if t:sub(pos, pos + #s - 1) == s then
      chosen[i] = s
      if walk(i + 1, pos + #s) then return true end
    end
    local v = VARIANT[s]
    if v and t:sub(pos, pos + #v - 1) == v then
      chosen[i] = v
      if walk(i + 1, pos + #v) then return true end
    end
    return false
  end
  if not walk(1, 1) then return nil end
  return chosen
end

-- comment 形如 "beq7'sian1"（delimiter[0]＝撇號作音節分隔）。
-- 例外：字音表裏有幾條多字條目个碼弗按規範寫（音節之間嘸空格，
-- 例如 如何 naeq8han1、如何然 na6nen2），librime 會當佢一隻
-- 偽音節。此地按「字母＋末位聲調數字」重新切分，自動歸正成
-- 多音節——迭兩條就照詞个樣處理（naeqhan / nanen），弗必改詞典。
local function split_code(comment)
  local syls, cur = {}, ''
  for ch in comment:gmatch('.') do
    if ch == ' ' or ch == "'" then
      if cur ~= '' then
        syls[#syls + 1] = cur
        cur = ''
      end
    else
      cur = cur .. ch
      if ch:match('%d') then          -- 聲調數字＝音節結束
        syls[#syls + 1] = cur
        cur = ''
      end
    end
  end
  if cur ~= '' then syls[#syls + 1] = cur end
  return syls
end

local function is_code(comment)
  if comment == '' or comment:find("[^%a%d' ]") then return false end
  local syls = split_code(comment)
  if #syls == 0 then return false end
  for _, s in ipairs(syls) do
    if not s:match('^[a-z]+[1-8]$') then return false end
  end
  return true
end

-- ============ 詞首字同字母異調補撇 ============
-- librime 个 DistinctTranslation 會擔同詞異碼个候選按文本去脫，
-- 蠻好 me1'hau3 / me2'hau3 祇剩一碼。首字若有「字母一樣、聲調兩樣」
-- 个讀音（me1/me2），小撇就跟脫調變——迭兩種拼音文（'mehau、mehau）
-- 全部要用 reverse db 補轉來。異字母个讀音（人 zen2/gnin2）各自
-- 有各自个輸入，弗需要補。
local rdb = nil
local rdb_failed = false

local function first_char_alt_tones(first_char, base_bare, base_tone)
  if rdb_failed or not first_char or first_char == '' then
    return {}
  end
  local ok, v = true, ''
  if rdb then
    ok, v = pcall(function() return rdb:lookup(first_char) end)
  else
    ok, rdb = pcall(ReverseDb, 'build/wugniu_suwu.reverse.bin')
    if ok and rdb then
      ok, v = pcall(function() return rdb:lookup(first_char) end)
    end
  end
  if not ok or not rdb then
    rdb_failed = true
    return {}
  end
  local alts = {}
  if v and v ~= '' then
    for s in v:gmatch('[^ ]+') do
      local b = s:gsub('[1-8]$', '')
      local t = tonumber(s:match('[1-8]$') or '')
      if b == base_bare and t and t ~= base_tone then
        alts[#alts + 1] = t
      end
    end
  end
  return alts
end

-- ============ 大小寫還原 ============
-- 拿候選覆蓋个原大小寫輸入，按字母順序套到拼音文上；
-- 字母數對弗齊（簡拼等）就祇保首字母大寫。
local function apply_case(out, typed)
  if not typed or typed == '' then return out end
  local tl = {}
  for ch in typed:gmatch('%a') do tl[#tl + 1] = ch end
  if #tl == 0 then return out end
  local n_out = select(2, out:gsub('[a-z]', '%0'))
  if n_out == #tl then
    local i = 0
    return (out:gsub('[a-z]', function(c)
      i = i + 1
      if tl[i]:upper() == tl[i] then return c:upper() end
      return c
    end))
  end
  local first = typed:match('%a')
  if first and first:upper() == first then
    return (out:gsub('[a-z]', string.upper, 1))
  end
  return out
end

-- ============ 詞間空格（前導式＋預輸入提示）＋句首自動大寫 ============
-- 架構（v1.9）：選詞後向組編區推入一隻空格（push_input(' ')）。
-- 迭隻空格一物兩用：
--   1. 預輸入提示——組編框裏向看得見一隻空格符號，提醒用戶
--      「有隻空格待輸入，下個詞辰光自動上屏」；
--   2. 佢本生就是詞間分隔空格——下個詞个字母跟拉佝後頭進
--      組編區，上屏辰光一道出去（' word2）。
-- 標點打下去：清脫指示空格，標點緊貼詞後（word1,）；
-- 誤打空格也拉指示裏向，一道清脫（自動修正）；
-- 回車：清脫（行末弗留）；手動再敲空格：再挂一隻（多格距離）。
-- 句首自動大寫：會話起始、句末標點（. ! ?）、回車之後，下一詞
-- 首字母自動大寫；用戶親自敲个大寫永遠優先。
local cap_next = true
-- 點選候選（手機候選欄／鼠標）走 API 直選，弗產按鍵事件，處理器
-- 攔弗著。辦法：每趟按鍵開頭對 commit_history 檢查「未經處理个
-- 提交」（type 弗是 thru 个新記錄），補推指示空格。
local last_hist_text = nil
local ext_pending = false
local cap_lock = false
-- 自最近句首點以來，本方案發出到正文个字符數：
-- 退格刪到 0，就等於回到句首，重新打開自動大寫
local chars_since_start = 0

-- 標點鍵：其後欠一隻空格
local PUNCT_KEYS = {
  [44] = true,  -- ,
  [46] = true,  -- .
  [59] = true,  -- ;
  [58] = true,  -- :
  [33] = true,  -- !
  [63] = true,  -- ?
  [47] = true,  -- /
  [39] = true,  -- '
}

-- 選詞之後个共同收尾：記字符數、關句首大寫（句末鍵当次除外）、
-- 推入「待輸入空格」指示（佢就是下個詞个分隔空格）。
-- 全部親手做，弗依賴通知。
local function after_commit(ctx)
  pcall(function()
    local e = ctx.commit_history:back()
    if e and e.text then
      chars_since_start = chars_since_start + #e.text
      last_hist_text = e.text
    end
  end)
  if not cap_lock then
    cap_next = false
  end
  -- 組編區還有剩餘輸入（分段選擇）辰光弗好挂指示空格——
  -- push_input 會接拉尾巴，壞脫後頭个輸入；分隔空格改由
  -- 過濾器拉非末段候選文本尾部補。
  pcall(function()
    if ctx.input == '' then
      ctx:push_input(' ')
    end
  end)
end

-- ============ 處理器：選詞收尾＋標點記賬＋大寫轉小寫 ============
-- 排拉 recognizer 前（q/x 反查鍵搶弗著）、speller 前
-- （大寫鍵必須先轉小寫再進組編區）。
function M.case_processor(key, env)
  if key:release() or key:ctrl() or key:alt() or key:super() or key:caps() then
    return 2  -- kNoop
  end
  local ctx = env.engine.context
  local inp = ctx.input

  -- 註釋漢字恆用吳語漢字檔（開關已從菜單刪脫，此地強制開）
  if not ctx:get_option('varients_wy') then
    ctx:set_option('varients_wy', true)
  end

  -- 外部提交檢測：commit_history 出現新个非 thru 記錄＝有隻
  -- 提交（點選候選等）繞過了處理器，記賬並挂起「下詞前導空格」。
  -- thru＝引擎記錄个未處理按鍵（如直通標點），弗是提交，弗理。
  do
    local ok, ext = pcall(function()
      local h = ctx.commit_history
      if h:empty() then
        last_hist_text = nil
        return nil
      end
      local r = h:back()
      if r.type == 'thru' then return nil end
      if r.text == '' or r.text == last_hist_text then return nil end
      return r.text
    end)
    if ok and ext then
      last_hist_text = ext
      chars_since_start = chars_since_start + #ext
      if not cap_lock then
        cap_next = false
      end
      ext_pending = true
      log.info('lumozy ext-commit [' .. ext .. ']')
    end
  end

  local kc = key.keycode
  log.info('lumozy enter v1.10 kc=' .. kc .. ' inp=[' .. inp ..
    '] cap=' .. tostring(cap_next))

  -- 句末檢測：. ! ?、回車 → 下一詞首字母大寫
  -- （本鍵当次个上屏弗清 cap_next，故設 cap_lock）
  cap_lock = false
  if kc == 46 or kc == 33 or kc == 63 or kc == 13 or kc == 0xFF0D then
    cap_next = true
    cap_lock = true
    chars_since_start = 0
  end
  -- 組編區裏衹有「待輸入空格」指示个場化：
  --   標點 → 清脫指示（含誤打个），標點緊貼詞後
  --   回車 → 清脫，原始換行
  --   空格 → 再挂一隻（多格距離）
  --   退格 → 編輯器自然刪脫一隻指示空格
  --   字母 → 落下去正常進組編，指示空格隨詞一道上屏
  local spaces_only = inp ~= '' and inp:match('^%s*$') ~= nil
  if spaces_only then
    if kc == 0xFF08 then
      -- 退格刪指示空格：同步遞減字符計數（弗然「刪光可見詞」
      -- 之後計數還賸一截，重輸弗會恢復句首大寫）
      chars_since_start = chars_since_start - 1
      if chars_since_start < 0 then
        chars_since_start = 0
      end
      if chars_since_start == 0 then
        cap_next = true
      end
      return 2  -- 編輯器自然刪脫一隻空格
    end
    if PUNCT_KEYS[kc] then
      -- 清脫指示（含誤打多个空格），標點緊貼詞後；
      -- 再挂一隻——標點之後个下一詞照樣有前導空格
      pcall(function()
        ctx:clear()
        ctx:push_input(' ')
      end)
      log.info('lumozy cling: indicator re-armed after punct')
      return 0  -- kRejected，標點直通
    elseif kc == 13 or kc == 0xFF0D then
      pcall(function() ctx:clear() end)
      return 2
    elseif kc == 32 then
      pcall(function() ctx:push_input(' ') end)
      return 1
    end
    -- 別个鍵（字母、退格、數字等）落下去正常處理
  end

  -- 組編區空个標點（例如詞上屏、指示空格撥退格彈脫之後）：
  -- 標點直通，並挂一隻指示空格，保證標點後个下一詞有空格
  if PUNCT_KEYS[kc] and inp == '' then
    if not spaces_only then
      pcall(function() ctx:push_input(' ') end)
    end
    return 0  -- kRejected
  end

  -- 詞中標點：親手擔詞上屏（標點本身弗進組編，原樣落盤：
  -- kRejected＝弗喫鍵）。必須攔拉 key_binder 前頭——default
  -- 預設把組編中个 , . 綁成翻頁，弗攔就變翻頁哉。
  if PUNCT_KEYS[kc] and inp ~= '' then
    local ok = ctx:confirm_current_selection()
    log.info('lumozy punct confirm=' .. tostring(ok))
    after_commit(ctx)
    return 0  -- kRejected
  end

  -- 數字鍵選詞：弗攔，交畀 rime 个 selector——佢按「當前頁第幾個」
  -- 定位。弗好自家調 ctx:select(n)：librime 个 Select 用全局序號，
  -- 翻頁之後選會揀錯候選（整句候選一記頭上屏，剩餘部分廢脫）。
  -- 點選／數字選詞个提交由下頭个外部提交檢測補記賬。

  -- 空格鍵：組編中＝選詞（立即完成＋挂指示空格）；
  -- 非組編＝直通，用戶手動加个真實空格。
  if kc == 32 then
    if inp ~= '' then
      local ok = ctx:confirm_current_selection()
      log.info('lumozy space confirm=' .. tostring(ok))
      after_commit(ctx)
      return 1
    end
    return 2
  end

  -- 非組編退格：正文删一隻字符；刪到句首點＝回到句首，
  -- 重新打開自動大寫
  if kc == 0xFF08 and inp == '' then
    chars_since_start = chars_since_start - 1
    if chars_since_start <= 0 then
      chars_since_start = 0
      cap_next = true
    end
    return 2
  end

  resync(inp)
  if inp:sub(1, 1) == '/' then
    return 2  -- 符號查詢段（/xx），照原樣處理
  end
  local is_word_key = (kc >= 65 and kc <= 90)
    or (kc >= 97 and kc <= 122)
  if is_word_key then
    -- 點選提交之後个頭一隻字母：補推指示空格（分隔隨詞上屏）
    if ext_pending and inp == '' then
      pcall(function() ctx:push_input(' ') end)
      ext_pending = false
      orig_input = ' '
    end
    if kc >= 65 and kc <= 90 then            -- A–Z
      if ctx.caret_pos ~= #inp then return 2 end
      orig_input = (orig_valid(inp) and orig_input or inp) .. string.char(kc)
      ctx:push_input(string.char(kc + 32))
      return 1  -- kAccepted
    elseif kc >= 97 and kc <= 122 or (kc == 39 and inp ~= '') then  -- a–z、'
      if ctx.caret_pos ~= #inp then return 2 end
      orig_input = (orig_valid(inp) and orig_input or inp) .. string.char(kc)
    end
  end
  ext_pending = false
  return 2
end

-- ============ 過濾器：漢字候選 ⇄ 拼音文互換 ============
-- 祇換 comment 恰是音節碼个候選；標點、反查（q/x 開頭）、
-- 用戶短語等原樣放行。同文本同註釋个重複行去脫
-- （代替 uniquifier——佢會拿同拼音文弗同漢字个兩行併掉）。
function M.romazy_filter(input, env)
  local ctx = env.engine.context
  local inp = ctx.input or ''
  local skip_all = inp:match('^q[a-z\']*$') ~= nil
    or inp:match('^x[hspnz]*$') ~= nil
  local orig = orig_valid(inp) and orig_input or inp
  -- 註釋開關：有註釋＝拼音文＋漢字；無註釋＝淨拼音文，
  -- 拼音文相同个候選合併成一條
  local show_comment = true
  pcall(function()
    -- rime 開關是布爾：false＝第一狀態（有註釋），true＝第二（無）
    if ctx:get_option('lumozy_comment') then
      show_comment = false
    end
  end)

  local seen = {}
  for cand in input:iter() do
    local code = cand.comment or ''
    if code == '' then
      local ok, g = pcall(function() return cand:get_genuine() end)
      if ok and g then code = g.comment or '' end
    end
    if skip_all or not is_code(code) then
      local key = (cand.text or '') .. '\1' .. code
      if not seen[key] then
        seen[key] = true
        yield(cand)
      end
    else
      local hanzi = cand.text
      local syls = split_code(code)
      local bare, tone = {}, {}
      for i, s in ipairs(syls) do
        bare[i] = s:gsub('[1-8]$', '')
        tone[i] = tonumber(s:match('[1-8]$') or '')
      end
      -- 敲入字母（該候選覆蓋个區間，保留大小寫，淨留字母）
      local typed_full = orig:sub(cand.start + 1, cand._end)
      local t = (typed_full:gsub('[^%a]', '')):lower()
      -- 逐音節揀原式／變體式；敲弗落（簡拼、容差）就原式
      local chosen = match_variant(bare, t)
      for i, b in ipairs(bare) do
        if not chosen or not chosen[i] then
          chosen = chosen or {}
          chosen[i] = b
        end
      end

      -- 分詞：句子候選按組件劃組，連續單字組件併作一個詞組
      -- （一眼詞敲進來、詞典裏嘸該讀音組合个場化），
      -- 多字詞典詞條各自成詞，詞搭詞之間空開。
      -- 注意：simplifier 會擔句子候選包成 shadow，to_sentence
      -- 必須對 get_genuine() 拆出來个本尊調。
      local counts = nil
      local target = cand
      local ok_g, genuine =
        pcall(function() return cand:get_genuine() end)
      if ok_g and genuine then target = genuine end
      local ok_s, sent = pcall(function() return target:to_sentence() end)
      if ok_s and sent then
        local ok_e, comps =
          pcall(function() return sent.entrys end)
        if ok_e and type(comps) == 'table' and #comps > 0 then
          local run, total, good = 0, 0, true
          counts = {}
          for _, comp in ipairs(comps) do
            local ok_t, ctext =
              pcall(function() return comp.text end)
            -- 漢字 text 个 # 是字節數，必須用 utf8.len 數字符
            local n = (ok_t and ctext) and (utf8.len(ctext) or 0) or 0
            if n <= 0 then good = false; break end
            if n == 1 then
              run = run + 1
            else
              if run > 0 then counts[#counts + 1] = run; run = 0 end
              counts[#counts + 1] = n
            end
            total = total + n
          end
          if run > 0 then counts[#counts + 1] = run end
          if not good or total ~= #syls then counts = nil end
        end
      end
      if not counts then counts = { #syls } end

      local groups = {}
      local idx = 1
      for _, n in ipairs(counts) do
        local forms = {}
        for i = 1, n do forms[i] = chosen[idx + i - 1] end
        groups[#groups + 1] = { forms = forms, tone = tone[idx] }
        idx = idx + n
      end
      local function rom_of(gs)
        local parts = {}
        for _, g in ipairs(gs) do
          local forms = {}
          for i, f in ipairs(g.forms) do forms[i] = f end
          parts[#parts + 1] = word_from_forms(forms, g.tone)
        end
        return table.concat(parts, ' ')
      end
      local rom = #groups > 0 and rom_of(groups) or nil

      -- 首字同字母異調：補出帶弗同小撇个變體行
      local roms = {}
      if rom then
        roms[#roms + 1] = rom
        local h0 = hanzi ~= '' and
          hanzi:sub(1, utf8.offset(hanzi, 2) - 1) or ''
        for _, t2 in ipairs(first_char_alt_tones(h0, bare[1], tone[1])) do
          local g2 = {}
          for i, g in ipairs(groups) do g2[i] = g end
          g2[1] = { forms = groups[1].forms, tone = t2 }
          local r2 = rom_of(g2)
          if r2 and r2 ~= rom then roms[#roms + 1] = r2 end
        end
      end

      -- 句首自動大寫：淨對「組編區首段」生效（前綴衹有空格），
      -- 且用戶全程敲小寫（親自敲个大寫永遠優先）。
      -- 分段選詞辰光後續各段弗好也大寫。
      local prefix_blank = inp:sub(1, cand.start):match('^%s*$') ~= nil
      local auto_cap = cap_next and prefix_blank and typed_full ~= ''
        and typed_full == typed_full:lower()
      -- 分段選擇：本候選弗喫完整个輸入（後頭還有剩餘），
      -- 即「詞之一」，上屏文本尾部補一隻空格——敲四段選四次
      -- 就出三隻空格，即四個詞。
      local seg_sep = (cand._end < #inp) and ' ' or ''
      for ri, r in ipairs(roms) do
        -- 有註釋：同樣拼音文弗同漢字各自成條；
        -- 無註釋：拼音文相同就合併（key 淨用拼音文）
        local key = show_comment and (r .. '\1' .. hanzi) or r
        if not seen[key] then
          seen[key] = true
          r = apply_case(r, typed_full)
          if auto_cap then
            r = r:gsub('[a-z]', string.upper, 1)
          end
          local nc = Candidate(cand.type, cand.start, cand._end,
                               r .. seg_sep,
                               show_comment and hanzi or '')
          if typed_full and typed_full ~= '' then
            nc.preedit = typed_full
          else
            nc.preedit = cand.preedit
          end
          yield(nc)
        end
      end
      if not rom and not seen[(cand.text or '') .. '\1' .. hanzi] then
        seen[(cand.text or '') .. '\1' .. hanzi] = true
        yield(cand)
      end
    end
  end
end

return M
