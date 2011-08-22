--[[ <HCExtension>
@name			IgnoreOnceVisitedSites
@author			Inversion (yura.des@gmail.com)
@version       2.0.2
@description	Do not cache contents of very seldom visited sites
@event			Init/on_Init
@event			Options/on_Options
@event			BeforeRequestHeaderSend/on_BeforeRequestHeaderSend
@event			Destroy/on_Destroy
</HCExtension> ]]

-- Version history
	-- 2.0.2 (17.06.11)
		-- Исправил влияние расширения на опцию «Только для GET-запросов». При включеном расширении, отключение этого флажка не влияло на кеширование POST-запросов, они всегда не сохранялись.
	-- 2.0.1 (01.06.11) — Improvements
		-- расширения теперь находит свои файлы, если поместить его в отдельную папку
		-- улучшена обработка запросов, теперь расширение не вызывается, если запрос берется из кэша, или был блокирован
		-- строки, которые расширение выводит в колонке "Правила", теперь не должны затирать сообщение от других расширений
		-- сокращено сообщение о проверке Referrer в мониторе
		-- добавлено удаление глобальных переменных при закрытии расширения
	-- 2.0.0 (10.05.11) — Huge improvement. Thanks to Михаил from HandyCache forum
		-- Stats is not based on files now (no more I/O operations on request processing)
		-- Stats is stored in IgnoreOnceVisitedSitesDB.txt, config in IgnoreOnceVisitedSites.ini
		-- UI for config and stats
		-- Automatic stats saving every hour
		-- lfs.dll is not required anymore
	-- 1.0.0 (07.05.11) — First public release
	-- 0.90.0 (28.11.10) — Beta testing started

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--   Изменить настройки теперь можно через кнопку «Настройки расширения» (находится справа от списка установленных расширений)
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------



g_name = re.find(hc.script_name, [[([^\\]+)\.lua$]], 1)
g_extensionRoot = re.replace(hc.script_name, g_name..[[\.lua$]], '')

g_secondsInHour = 60*60
g_secondsInDay = g_secondsInHour*24
g_secondsInMonth = g_secondsInDay*30
g_saveEvery = g_secondsInHour*1 -- 1 hour (как часто сохранять статистику на диск)


function on_Init()

	-- default config values
	hc.set_global_table_item(g_name, 'ini_lastSaveTime', os.time())
	hc.set_global_table_item(g_name, 'ini_visitsCountToStartCache', 3)
	hc.set_global_table_item(g_name, 'ini_daysBetweenVisits', 3) -- 3 days — сколько минимум должно пройти времени от последнего визита, чтобы засчитать еще один полноценный визит
	hc.set_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats', 2) -- 2 months — сколько должно пройти времени от последнего визита, чтобы обнулить статистику посещений сайта (удалить сайт из базы), не достигшего порогового значения посещений

	local f = io.open(g_extensionRoot..g_name..'.ini', 'r')
	if (f) then
																																										hc.put_to_log('ini loading...')
		while true do
			s = f:read("*line")
			if s then 
				local pos = string.find(s, " = ")
				local param = string.sub(s, 0, pos-1)
				local value = tonumber(string.sub(s, pos+3))
																																										hc.put_to_log('ini_'..param..'« = »'..value)
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
	Label1._ = { caption='Сколько посещений нужно, чтобы зачислять сайт в "регулярно посещаемые" и начинать кэшировать:', WordWrap=true, top=8, left=10, height=96, width=300}
	Edit1 = VCL.Edit(Form, "Edit1")
	Edit1._ = {text=hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache'), top=Label1.top+3, left=340, width=30, height=96}
	
	Label2 = VCL.Label(Form, "Label2")
	Label2._ = {caption='Сколько минимум должно пройти дней от последнего визита на сайт, чтобы засчитать еще один полноценный визит:', WordWrap=true, top=41, left=10, height=96, width=320}
	Edit2 = VCL.Edit(Form, "Edit2")
	Edit2._ = {text=hc.get_global_table_item(g_name, 'ini_daysBetweenVisits'), top=Label2.top+3, left=340, width=30, height=96}
	
	Label3 = VCL.Label(Form, "Label3")
	Label3._ = {caption='Сколько должно пройти месяцев от последнего визита, чтобы обнулить статистику посещений сайта, ещё не достигшего порогового значения посещений:', WordWrap=true, top=73, left=10, height=96, width=320}
	Edit3 = VCL.Edit(Form, "Edit3")
	Edit3._ = {text=hc.get_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats'), top=Label3.top+10, left=340, width=30}

	Label4 = VCL.Label(Form, "Label4")
	Label4._ = {caption='Сайт : последний визит : всего посещений', top=118, left=11, width=320}
	local list = {}
	local DB = hc.get_global(g_name..'DB')
		
	for domain, stats in pairs(DB) do
		local lastdate = stats[1]
		local visits = stats[2]
																																									-- hc.put_to_log(domain..' : '..lastdate..' : '..visits)
		table.insert(list, domain..' : '..lastdate..' : '..visits)
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
	
	-- обновляем глобальные переменные параметров
	hc.set_global_table_item(g_name, 'ini_visitsCountToStartCache', tonumber(Edit1.text))
	hc.set_global_table_item(g_name, 'ini_daysBetweenVisits', tonumber(Edit2.text))
	hc.set_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats', tonumber(Edit3.text))
	
	-- обновляем глобальшую таблицу статистики
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
				local domain = string.sub(s, 0, pos-1)
				local lastdate = tonumber(string.sub(s, pos+3, pos2-1))
				local visits = tonumber(string.sub(s, pos2+3))
																																										-- hc.put_to_log(domain..' : '..lastdate..' : '..visits)
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
	-- обновляем дату последнего сохранения
	hc.set_global_table_item(g_name, 'ini_lastSaveTime', os.time())
		
	-- сохраняем параметры
	f = io.open(g_extensionRoot..g_name..'.ini', 'w')
	if (f) then
		for param, value in pairs(hc.get_global(g_name)) do
			f:write(param:sub(5)..' = '..value..'\n')
		end
		f:close()
	else
																																										hc.put_to_log('ini save failed')
	end
	
	-- сохраняем статистику
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
	
	-- очистка глобальных переменных
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
		-- если посещений недостаточно и последний визит был ранее чем 2 месяца назад — значит это не регулярно посещаемый сайт
		if visits < hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache')  and  lastdate < os.time() - hc.get_global_table_item(g_name, 'ini_lastVisitAgeInMonthsToResetStats') * g_secondsInMonth   then
			-- удаляем сайт из статистики (обнуление)
			hc.set_global_table_item(g_name..'DB', domain)
																																									hc.put_to_log('remove '..domain)
		end
	end
	
end


function on_BeforeRequestHeaderSend()
	g_myMonitor_string = ''
																																										hc.put_to_log('**** on_BeforeRequestHeaderSend *****')
	
	-- игнорируем запросы на получение иконок сайтов (не считаем за визит на сайт), которых множество делается при отображении результатов поиска в поисковиках http://.*/favicon.ico
	if string.find(hc.url, 'favicon.ico', 1, true) then
		hc.action = "dont_save"
		g_myMonitor_string = "Skipping favicon request"
		hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
		return
	end
	
	-- не рассматриваем POST-запросы (не считаем за визит на сайт)
	if hc.method == 'POST' then
		-- hc.action = "dont_save"
		return
	end
	
	-- рассматриваем запросы без Referrer, а если есть Referrer, то в относительно него
		local fullReferrerDomain = nil
		local referrerDomain = nil
		local checkDomain = nil
		-- берем Referrer
		local referrer = re.find(hc.request_header, [[[Rr]eferer: *([^ \r\n]+)]], 1)
																																										hc.put_to_log('referrer='..tostring(referrer))
		-- если есть Referrer, то рассматриваем его домен, если нет, то домен запроса
		if referrer then
			-- берем полный домен урла реферера
			fullReferrerDomain = string.lower( re.find(referrer, [[://(?:www\.)?([^/:]+)]], 1) )
																																										hc.put_to_log('fullReferrerDomain='..fullReferrerDomain)
			-- берем основной домен (для "gol.habrahabr.ru" надо взять "habrahabr.ru")
			referrerDomain = re.find(fullReferrerDomain, [[([^/:.]+\.[^/:.]{1,4}\.[^/:.]{1,4}\.[^/:.]{1,4}|[^/:.]+\.[^/:.]{1,4}\.[^/:.]{1,4}|[^/:.]+\.[^/:.]{1,4})$]], 1)
																																										hc.put_to_log('referrerDomain='..referrerDomain)
			checkDomain = referrerDomain
			g_myMonitor_string = "Referrer "..checkDomain.." - "
		else
			-- берем полный домен урла запроса
			local fullDomain = string.lower( re.find(hc.url, [[://(?:www\.)?([^/:]+)]], 1) )
																																										hc.put_to_log('fullDomain='..fullDomain)
			-- берем основной домен
			local domain = re.find(fullDomain, [[([^/:.]+\.[^/:.]{1,4}\.[^/:.]{1,4}\.[^/:.]{1,4}|[^/:.]+\.[^/:.]{1,4}\.[^/:.]{1,4}|[^/:.]+\.[^/:.]{1,4})$]], 1)
																																										hc.put_to_log('domain='..domain)
			checkDomain = domain
		end
																																										hc.put_to_log('checkDomain='..checkDomain)
		
	local domain_stats = hc.get_global_table_item(g_name..'DB', checkDomain)
	-- если домен есть в базе
	if domain_stats then
																																										hc.put_to_log('** домен есть в базе **')
		local lastdate = domain_stats[1]
																																										hc.put_to_log('lastdate='..lastdate)
		-- количество визитов
		local visits = domain_stats[2]
																																										hc.put_to_log('visits='..visits)
		-- если со времени последнего визита прошло > 3 дней
		if lastdate < os.time() - g_secondsInDay*hc.get_global_table_item(g_name, 'ini_daysBetweenVisits') then
			-- увеличиваем количество визитов и запоминаем дату этого визита как последнюю
			visits = visits+1
			hc.set_global_table_item(g_name..'DB', checkDomain, {os.time(), visits})
																																										hc.put_to_log('visits='..visits)
		end
			
		-- если визитов всё еще < порогового значения...
		if visits < hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache') then
			-- не кэшируем
																																									hc.put_to_log('-- dont_save --')
			hc.action = "dont_save"
			g_myMonitor_string = g_myMonitor_string.."Visited "..tostring(visits).."/"..hc.get_global_table_item(g_name, 'ini_visitsCountToStartCache')
			hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
		-- если же достаточно визитов...
		else
			-- кэшируем
																																										hc.put_to_log('++ save ++')
			g_myMonitor_string = g_myMonitor_string.."Visited often"
			hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
		end
		
	-- если же сайта нет в базе — создаем запись
	else
																																										hc.put_to_log('** сайта нет в базе — создаем запись **')
		-- не кэшируем
		hc.action = "dont_save"
		-- запоминаем дату этого визита и ставим начальное количество визитов
		hc.set_global_table_item(g_name..'DB', checkDomain, {os.time(), 1})
		g_myMonitor_string = g_myMonitor_string.."New domain: "..checkDomain
		hc.monitor_string = hc.monitor_string .. g_myMonitor_string..' '
	end -- if  домен есть в базе
	
	-- если давно не сохранялись — сохраняемся
	if hc.get_global_table_item(g_name, 'ini_lastSaveTime') < os.time()-g_saveEvery  then
		saveData()
	end
end


