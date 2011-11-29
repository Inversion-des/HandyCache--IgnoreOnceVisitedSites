--[[ <HCExtension>
@name			IgnoreOnceVisitedSites
@author			Inversion (yura.des@gmail.com)
@version       2.1.0
@description	Do not cache contents of very seldom visited sites
@event			Init/on_Init
@event			Options/on_Options
@event			BeforeRequestHeaderSend/on_BeforeRequestHeaderSend
@event			Destroy/on_Destroy
</HCExtension> ]]

-- Version history
	-- 2.1.0 (29.11.11)
		-- ������� ��������� ������������� ������� ���� "������.��"
		-- ��������� ����� ���� ���������� ������ � ����������� ���� � ���� ���������� �����������
	-- 2.0.2 (17.06.11)
		-- ���������� ������� ���������� �� ����� ������� ��� GET-��������. ��� ��������� ����������, ���������� ����� ������ �� ������ �� ����������� POST-��������, ��� ������ �� �����������.
	-- 2.0.1 (01.06.11) � Improvements
		-- ���������� ������ ������� ���� �����, ���� ��������� ��� � ��������� �����
		-- �������� ��������� ��������, ������ ���������� �� ����������, ���� ������ ������� �� ����, ��� ��� ����������
		-- ������, ������� ���������� ������� � ������� "�������", ������ �� ������ �������� ��������� �� ������ ����������
		-- ��������� ��������� � �������� Referrer � ��������
		-- ��������� �������� ���������� ���������� ��� �������� ����������
	-- 2.0.0 (10.05.11) � Huge improvement. Thanks to ������ from HandyCache forum
		-- Stats is not based on files now (no more I/O operations on request processing)
		-- Stats is stored in IgnoreOnceVisitedSitesDB.txt, config in IgnoreOnceVisitedSites.ini
		-- UI for config and stats
		-- Automatic stats saving every hour
		-- lfs.dll is not required anymore
	-- 1.0.0 (07.05.11) � First public release
	-- 0.90.0 (28.11.10) � Beta testing started

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--   �������� ��������� ������ ����� ����� ������ ���������� ����������� (��������� ������ �� ������ ������������� ����������)
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------



g_name = re.find(hc.script_name, [[([^\\]+)\.lua$]], 1)
g_extensionRoot = re.replace(hc.script_name, g_name..[[\.lua$]], '')

g_secondsInHour = 60*60
g_secondsInDay = g_secondsInHour*24
g_secondsInMonth = g_secondsInDay*30
g_saveEvery = g_secondsInHour*1 -- 1 hour (��� ����� ��������� ���������� �� ����)


function on_Init()

	-- default config values
	hc.set_global_table_item(g_name, 'ini_lastSaveTime', os.time())
	hc.set_global_table_item(g_name, 'ini_visitsCountToStartCache', 3)
	hc.set_global_table_item(g_name, 'ini_daysBetweenVisits', 3) -- 3 days � ������� ������� ������ ������ ������� �� ���������� ������, ����� ��������� ��� ���� ����������� �����
	hc.set_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats', 2) -- 2 months � ������� ������ ������ ������� �� ���������� ������, ����� �������� ���������� ��������� ����� (������� ���� �� ����), �� ���������� ���������� �������� ���������

	local f = io.open(g_extensionRoot..g_name..'.ini', 'r')
	if (f) then
																																										hc.put_to_log('ini loading...')
		while true do
			s = f:read("*line")
			if s then 
				local pos = string.find(s, " = ")
				local param = string.sub(s, 0, pos-1)
				local value = tonumber(string.sub(s, pos+3))
																																										hc.put_to_log('ini_'..param..'� = �'..value)
				hc.set_global_table_item(g_name, 'ini_'..param, value)
			else
				break 
			end
		end
		f:close()
																																										hc.put_to_log('ini loading...done')
	else
																																										hc.put_to_log('ini load failed')
	end
	
	local f = io.open(g_extensionRoot..g_name..'DB.txt', 'r')
	if (f) then
																																										hc.put_to_log('DB loading...')
		local s
		local DB = {}
		while true do
			s = f:read("*line")
			if s then 
				local pos = string.find(s, " : ")
				local pos2 = string.find(s, " : ", pos+1)
				local domain = string.sub(s, 0, pos-1)
				local lastdate = tonumber(string.sub(s, pos+3, pos2-1))
				local visits = tonumber(string.sub(s, pos2+3))
																																										-- hc.put_to_log(domain..' : '..lastdate..' : '..visits)
				if domain and visits and lastdate then
					DB[domain] = {lastdate, visits}
				end
			else
				break 
			end
		end
		hc.set_global(g_name..'DB', DB)
		f:close()
																																										hc.put_to_log('DB loading...done')
	else
																																										hc.put_to_log('DB load failed')
	end
	
	clearVerySeldomVisitedSitesFromDB()
end

function on_Options()
	require "vcl"
	Form = VCL.Form('Form')
	x, y, w, h = hc.window_pos()
	Form._ = { Caption=g_name, width=386, height=507, BorderStyle='Fixed3D' }
	Form._ = { left=x+(w-Form.width)/2, top=y+(h-Form.height)/2 }
	
	Label1 = VCL.Label(Form, "Label1")
	Label1._ = { caption='������� ��������� �����, ����� ��������� ���� � "��������� ����������" � �������� ����������:', WordWrap=true, top=8, left=10, height=96, width=300}
	Edit1 = VCL.Edit(Form, "Edit1")
	Edit1._ = {text=hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache'), top=Label1.top+3, left=340, width=30, height=96}
	
	Label2 = VCL.Label(Form, "Label2")
	Label2._ = {caption='������� ������� ������ ������ ���� �� ���������� ������ �� ����, ����� ��������� ��� ���� ����������� �����:', WordWrap=true, top=41, left=10, height=96, width=320}
	Edit2 = VCL.Edit(Form, "Edit2")
	Edit2._ = {text=hc.get_global_table_item(g_name, 'ini_daysBetweenVisits'), top=Label2.top+3, left=340, width=30, height=96}
	
	Label3 = VCL.Label(Form, "Label3")
	Label3._ = {caption='������� ������ ������ ������� �� ���������� ������, ����� �������� ���������� ��������� �����, ��� �� ���������� ���������� �������� ���������:', WordWrap=true, top=73, left=10, height=96, width=320}
	Edit3 = VCL.Edit(Form, "Edit3")
	Edit3._ = {text=hc.get_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats'), top=Label3.top+10, left=340, width=30}

	Label4 = VCL.Label(Form, "Label4")
	Label4._ = {caption='���� : ��������� ����� : ����� ���������', top=118, left=11, width=320}
	local list = {}
	local DB = hc.get_global(g_name..'DB')
		
	for domain, stats in pairs(DB) do
		local lastdate = stats[1]
		local visits = stats[2]
																																									hc.put_to_log(domain..' : '..lastdate..os.date(' (%d/%m/%Y)',lastdate)..' : '..visits)
		table.insert(list, domain..' : '..lastdate..os.date(' (%d/%m/%Y)',lastdate)..' : '..visits)
	end
	table.sort(list)
	Memo1 = VCL.Memo(Form, "Memo1")
	Memo1._ = { parentfont=true, top=133, left=10, width=Form.clientwidth-20, height=297, scrollbars='ssVertical', wordwrap=false}
	Memo1:SetText(list)
	
	OkButton = VCL.Button(Form, "OkButton")
	OkButton._ = {onclick = "onOkButtonClick", width=100, left=161, caption = "OK", top= Form.clientheight-OkButton.height-10}
	CancelButton = VCL.Button(Form, "CancelButton")
	CancelButton._ = {onclick = "onCancelButtonClick", width=100, left=OkButton.left+OkButton.width+10, top=OkButton.top, caption = "Cancel"}
	
	Form:ShowModal()
	Form:Free()
	Form=nil
end

function onOkButtonClick(Sender)
	
	-- ��������� ���������� ���������� ����������
	hc.set_global_table_item(g_name, 'ini_visitsCountToStartCache', tonumber(Edit1.text))
	hc.set_global_table_item(g_name, 'ini_daysBetweenVisits', tonumber(Edit2.text))
	hc.set_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats', tonumber(Edit3.text))
	
	-- ��������� ���������� ������� ����������
	local DB = {}
	local s
	if Memo1:Count()>0 then list = Memo1:GetText() end
	if #list>0 then
		local i
		for i=1, #list do
			if list[i] then
				s = list[i]
				local pos = string.find(s, " : ")
				local pos2 = string.find(s, " : ", pos+1)
				local pos3 = string.find(s, " %(", pos+1)
				local domain = string.sub(s, 0, pos-1)
				local lastdate = tonumber(string.sub(s, pos+3, pos3-1))
				local visits = tonumber(string.sub(s, pos2+3))
																																										hc.put_to_log(domain..' : '..lastdate..' : '..visits)
				if domain and visits and lastdate then
					DB[domain] = {lastdate, visits}
				end
			end
		end
		hc.set_global(g_name..'DB', DB)
	end
	
	saveData()
	Form:Close()
end

function saveData()
																																										hc.put_to_log('* saveData *')
	-- ��������� ���� ���������� ����������
	hc.set_global_table_item(g_name, 'ini_lastSaveTime', os.time())
		
	-- ��������� ���������
	f = io.open(g_extensionRoot..g_name..'.ini', 'w')
	if (f) then
		for param, value in pairs(hc.get_global(g_name)) do
			f:write(param:sub(5)..' = '..value..'\n')
		end
		f:close()
	else
																																										hc.put_to_log('ini save failed')
	end
	
	-- ��������� ����������
	local DB = hc.get_global(g_name..'DB')
	f = io.open(g_extensionRoot..g_name..'DB.txt', 'w')
	if (f) then
		for domain, stats in pairs(DB) do
			local lastdate = stats[1]
			local visits = stats[2]
			f:write(domain..' : '..lastdate..' : '..visits..'\n')
		end
		f:close()
	else
																																										hc.put_to_log('DB save failed')
	end
end

function on_Destroy()
																																										hc.put_to_log('* on_Destroy *')
	saveData()
	
	-- ������� ���������� ����������
	hc.set_global(g_name)
	hc.set_global(g_name..'DB')
end

function onCancelButtonClick(Sender)
	Form:Close()
end




function clearVerySeldomVisitedSitesFromDB()
	local DB = hc.get_global(g_name..'DB')
	local i = 0
	
	for domain, stats in pairs(DB) do
		i = i+1
		local lastdate = stats[1]
		local visits = stats[2]
																																									-- hc.put_to_log(i)
																																									-- hc.put_to_log(lastdate)
																																									-- hc.put_to_log(os.time())
																																									-- hc.put_to_log(hc.get_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats') * g_secondsInMonth)
																																									-- hc.put_to_log(os.time() - hc.get_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats') * g_secondsInMonth)
		-- ���� ��������� ������������ � ��������� ����� ��� ����� ��� 2 ������ ����� � ������ ��� �� ��������� ���������� ����
		if visits < hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache')  and  lastdate < os.time() - hc.get_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats') * g_secondsInMonth   then
			-- ������� ���� �� ���������� (���������)
			hc.set_global_table_item(g_name..'DB', domain)
																																									hc.put_to_log('remove '..domain)
		end
	end
	
end


function on_BeforeRequestHeaderSend()
	g_myMonitor_string = ''
																																										hc.put_to_log('**** on_BeforeRequestHeaderSend *****')
	
	-- ���������� ������� �� ��������� ������ ������ (�� ������� �� ����� �� ����), ������� ��������� �������� ��� ����������� ����������� ������ � ����������� http://.*/favicon.ico
	if string.find(hc.url, 'favicon.ico', 1, true) then
		hc.action = "dont_save"
		g_myMonitor_string = "Skipping favicon request"
		hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
		return
	end
	
	-- �� ������������� POST-������� (�� ������� �� ����� �� ����)
	if hc.method == 'POST' then
		-- hc.action = "dont_save"
		return
	end
	
	-- ������������� ������� ��� Referrer, � ���� ���� Referrer, �� ������������ ����
		local checkDomain = nil
		
		-- ����� Referrer
		local referrer = re.find(hc.request_header, [[[Rr]eferer: *([^ \r\n]+)]], 1)
																																										hc.put_to_log('referrer='..tostring(referrer))
		-- ���� ���� Referrer, �� ������������� ��� �����, ���� ���, �� ����� �������
		local parseDomainString = referrer or hc.url
																																										hc.put_to_log('parseDomainString='..tostring(parseDomainString))
		-- ����� ������ ����� ���� ��������
		fullDomain = string.lower( re.find(parseDomainString, [[://(?:www\.)?([^/:]+)]], 1) )
																																										hc.put_to_log('fullDomain='..fullDomain)
		-- ���� ������������ punycode (.xn--p1ai) � ����������
		if fullDomain:find("xn--") then 
			fullDomain = decode_punycode(fullDomain)
																																										hc.put_to_log('decoded fullDomain='..fullDomain)
		end
		
		-- ����� �������� ����� (��� "user.habrahabr.ru" ���� ����� "habrahabr.ru")
		checkDomain = re.find(fullDomain, "([^/:.]+\.[^/:.]{1,4}\.[^/:.]{1,4}\.[^/:.]{1,5}|[^/:.]+\.[^/:.]{1,4}\.[^/:.]{1,5}|[^/:.]+\.[^/:.]{1,5})$", 1)
																																										hc.put_to_log('checkDomain='..tostring(checkDomain))
		if referrer then
			g_myMonitor_string = "Referrer "..checkDomain.." - "
		end
		
	local domain_stats = hc.get_global_table_item(g_name..'DB', checkDomain)
	-- ���� ����� ���� � ����
	if domain_stats then
																																										hc.put_to_log('** ����� ���� � ���� **')
		local lastdate = domain_stats[1]
																																										hc.put_to_log('lastdate='..lastdate)
		-- ���������� �������
		local visits = domain_stats[2]
																																										hc.put_to_log('visits='..visits)
		-- ���� �� ������� ���������� ������ ������ > 3 ����
		if lastdate < os.time() - g_secondsInDay*hc.get_global_table_item(g_name, 'ini_daysBetweenVisits') then
			-- ����������� ���������� ������� � ���������� ���� ����� ������ ��� ���������
			visits = visits+1
			hc.set_global_table_item(g_name..'DB', checkDomain, {os.time(), visits})
																																										hc.put_to_log('visits='..visits)
		end
			
		-- ���� ������� �� ��� < ���������� ��������...
		if visits < hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache') then
			-- �� ��������
																																									hc.put_to_log('-- dont_save --')
			hc.action = "dont_save"
			g_myMonitor_string = g_myMonitor_string.."Visited "..tostring(visits).."/"..hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache')
			hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
		-- ���� �� ���������� �������...
		else
			-- ��������
																																										hc.put_to_log('++ save ++')
			g_myMonitor_string = g_myMonitor_string.."Visited often"
			hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
		end
		
	-- ���� �� ����� ��� � ���� � ������� ������
	else
																																										hc.put_to_log('** ����� ��� � ���� � ������� ������ **')
		-- �� ��������
		hc.action = "dont_save"
		-- ���������� ���� ����� ������ � ������ ��������� ���������� �������
		hc.set_global_table_item(g_name..'DB', checkDomain, {os.time(), 1})
		g_myMonitor_string = g_myMonitor_string.."New domain: "..checkDomain
		hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
	end -- if  ����� ���� � ����
	
	-- ���� ����� �� ����������� � �����������
	if hc.get_global_table_item(g_name, 'ini_lastSaveTime') < os.time()-g_saveEvery then
		saveData()
	end
end


function decode_punycode(str)
	-- "xn--80a1acny.xn--p1ai"
	local result = {}
	--local arr = str.split('.')
	for part in str:gmatch("[^.]+") do
		if part:find("xn--") then
			table.insert(result, hc.recode(part:sub(4), 1251+200000, 1251))
		else
			table.insert(result, part)
		end
	end
	return table.concat(result, ".")
end
