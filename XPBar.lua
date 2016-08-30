local addonName, addonTable = ...; 

FXP_Config = {
	ShowIncomplete = nil,
	LevelAlert = 1,
}
FXP_LastLevelAlert = 1;

function FXP_OnLoad(self)

	hooksecurefunc("ExpBar_Update", FXP_MainMenuExpBar_Update);
	hooksecurefunc("MainMenuExpBar_SetWidth", FXP_MainMenuExpBar_Update);
	hooksecurefunc("ExhaustionToolTipText", FXP_Tooltip);
	MainMenuExpBar:HookScript("OnMouseDown", FXP_ShowMenu);
			
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("PLAYER_LEAVING_WORLD");
	self:RegisterEvent("ADDON_LOADED");
	
	SLASH_FXP1 = "/xp";
	SlashCmdList["FXP"] = function(msg)
		FXP_PrintSummary();
	end
	
end

function FXP_OnEvent(self, event, arg1, arg2)
	if ( event == "PLAYER_ENTERING_WORLD" or (event == "ADDON_LOADED" and arg1 == addonName)) then
		self:RegisterEvent("QUEST_LOG_UPDATE");
		self:RegisterEvent("PLAYER_XP_UPDATE");
		self:RegisterEvent("UNIT_INVENTORY_CHANGED");	-- catch +XP heirlooms
		self:RegisterEvent("PLAYER_LEVEL_UP");
	elseif( event == "PLAYER_LEAVING_WORLD" ) then
		self:UnregisterEvent("QUEST_LOG_UPDATE");
		self:UnregisterEvent("PLAYER_XP_UPDATE");
		self:UnregisterEvent("UNIT_INVENTORY_CHANGED");
		self:UnregisterEvent("PLAYER_LEVEL_UP");
	elseif( event == "PLAYER_LEVEL_UP" ) then
		FXP_LevelAlert:Hide();
	end
	FXP_UpdateQuestXP();
	FXP_MainMenuExpBar_Update();
end

------------------------------------------------------
-- Internal utils
------------------------------------------------------

function FXP_PrintSummary()

	if (not FXP_CompleteQuestsXP) then FXP_UpdateQuestXP(); end
	
	if (FXP_CompleteQuestsXP == 0 and FXP_IncompleteQuestsXP == 0) then
		print(FXP_NO_XP);
		return;
	end
		
	-- replicate main XP line from Blizz XP bar tooltip
	local currXP = UnitXP("player");
	local nextXP = UnitXPMax("player");
	local percentXP = math.ceil(currXP/nextXP*100);
	local XPText = format( XP_TEXT, BreakUpLargeNumbers(currXP), BreakUpLargeNumbers(nextXP), percentXP );
	XPText = gsub(XPText, "\n", "");
	print(EXPERIENCE_COLON, XPText);
	
	local newXP = currXP;
	
	if (FXP_CompleteQuestsXP > 0) then
		newXP = newXP + FXP_CompleteQuestsXP;
		print("With Complete Quests:", FXP_TooltipInfo(currXP, nextXP, newXP));
	end
	
	if (FXP_IncompleteQuestsXP > 0) then
		newXP = newXP + FXP_IncompleteQuestsXP;
		print("With All Current Quests:", FXP_TooltipInfo(currXP, nextXP, newXP));
	end

	
end

function FXP_UpdateQuestXP()
	FXP_CompleteQuestsXP = 0;
	FXP_IncompleteQuestsXP = 0;

	if (GetNumQuestLogEntries() == 0) then
		return;	-- no quests!
	end
	
	local questIndex = 0;
	local playerMoney = GetMoney();
	
	repeat
		-- not doing for loop to GetNumQuestLogEntries() because
		-- stuff under collapsed headers gets indices higher than that
		questIndex = questIndex + 1;
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory = GetQuestLogTitle(questIndex);
		if (not isHeader) then
			
			-- muck with "complete" status the way builtin quest watch UI does
			local requiredMoney = GetQuestLogRequiredMoney(questIndex);			
			local numObjectives = GetNumQuestLeaderBoards(questIndex);
			if ( isComplete and isComplete < 0 ) then
				isComplete = false;	-- failed quest
			elseif ( numObjectives == 0 and playerMoney >= requiredMoney and not startEvent) then
				isComplete = true;	-- no objectives means "complete" (a la breadcrumb quest)
			end

			if (isComplete) then
				FXP_CompleteQuestsXP = FXP_CompleteQuestsXP + GetQuestLogRewardXP(questID);
			elseif (FXP_Config.ShowIncomplete) then
				FXP_IncompleteQuestsXP = FXP_IncompleteQuestsXP + GetQuestLogRewardXP(questID);
			end
		end
	until (title == nil);

	local currXP = UnitXP("player");
	local nextXP = UnitXPMax("player");
	if (currXP + FXP_CompleteQuestsXP > nextXP) then
		FXP_NotifyLevelAvailable();
	end
	
	return FXP_CompleteQuestsXP, FXP_IncompleteQuestsXP; -- we don't actually use; returned for debug
end

------------------------------------------------------
-- XP Bar additions
------------------------------------------------------

function FXP_MainMenuExpBar_Update()

	if (not FXP_CompleteQuestsXP) then FXP_UpdateQuestXP(); end
	
	local currXP = UnitXP("player");
	local nextXP = UnitXPMax("player");
	local xpBarEnd = (currXP / nextXP) * MainMenuExpBar:GetWidth();

	local color = {};
	color.r, color.g, color.b = MainMenuExpBar:GetStatusBarColor();

	-- TODO(?): break each bar in 2 parts so we can be blue up to exhaustion tick, purple after

	local newXP = currXP + FXP_CompleteQuestsXP;
	local completeBarEnd = (newXP / nextXP) * MainMenuExpBar:GetWidth();
	completeBarEnd = math.max(completeBarEnd, 0);
	completeBarEnd = math.min(completeBarEnd, MainMenuExpBar:GetWidth());
	if (newXP == currXP) then
	    FXP_XPExtraFillBar1Texture:Hide();
	else
		if (newXP > nextXP) then 
			color = ITEM_QUALITY_COLORS[2];
			color.a = 0.33;
		else
			color.a = 0.5;
		end
		
		FXP_UpdateBar(FXP_XPExtraFillBar1Texture, xpBarEnd, completeBarEnd, color);		
	end
	
	newXP = newXP + FXP_IncompleteQuestsXP;
	if (newXP == currXP) then
	    FXP_XPExtraFillBar2Texture:Hide();
	else
		local incompleteBarEnd = (newXP / nextXP) * MainMenuExpBar:GetWidth();
		incompleteBarEnd = math.max(incompleteBarEnd, 0);
		incompleteBarEnd = math.min(incompleteBarEnd, MainMenuExpBar:GetWidth());
		if (newXP > nextXP) then 
			color = ITEM_QUALITY_COLORS[2];
			color.a = 0.4;
		else
			color.a = 0.6;
		end
		
		FXP_UpdateBar(FXP_XPExtraFillBar2Texture, completeBarEnd, incompleteBarEnd, color);		
	end

end

function FXP_UpdateBar(barTexture, left, right, color)
	barTexture:Show();
    barTexture:SetPoint("TOPRIGHT", "MainMenuExpBar", "TOPLEFT", right, 0);
    barTexture:SetPoint("TOPLEFT", "MainMenuExpBar", "TOPLEFT", left, 0);
    barTexture:SetVertexColor(color.r, color.g, color.b, color.a);    
end
	
function FXP_Tooltip()

	if (not FXP_CompleteQuestsXP) then FXP_UpdateQuestXP(); end
	
	if (FXP_CompleteQuestsXP == 0 and FXP_IncompleteQuestsXP == 0) then return; end
	
	GameTooltip:AddLine(" ");
	
	local currXP = UnitXP("player");
	local nextXP = UnitXPMax("player");
	local newXP = currXP;
	
	if (FXP_CompleteQuestsXP > 0) then
		newXP = newXP + FXP_CompleteQuestsXP;
		GameTooltip:AddDoubleLine("With Complete Quests:", FXP_TooltipInfo(currXP, nextXP, newXP));
	end
	
	if (FXP_IncompleteQuestsXP > 0) then
		newXP = newXP + FXP_IncompleteQuestsXP;
		GameTooltip:AddDoubleLine("With All Current Quests:", FXP_TooltipInfo(currXP, nextXP, newXP));
	end
	
	GameTooltip:Show();

end

function FXP_TooltipInfo(currXP, nextXP, newXP)
	local info;
	if (newXP < nextXP) then
		info = string.format( XP_TEXT, newXP, nextXP, math.ceil(newXP/nextXP*100) );
		info = string.sub(info, 1, -2); -- strip newlines
	else
		info = string.format( UNIT_LEVEL_TEMPLATE, UnitLevel("player") + 1);
	end
	return info;
end

------------------------------------------------------
-- Notify when enough complete quest XP to level
------------------------------------------------------
	
function FXP_NotifyLevelAvailable()
	
	if (not FXP_Config.LevelAlert) then return; end
	
	local nextLevel = UnitLevel("player") + 1;
	if (nextLevel <= FXP_LastLevelAlert) then return; end
	FXP_LastLevelAlert = nextLevel;
	
	local text = string.format(FXP_LEVEL_UP_FORMAT, nextLevel);
	FXP_LevelAlertText:SetText(text);

	-- adjust to fit on screen if needed
	local left, bottom, width, height = FXP_LevelAlert:GetRect();
	local diff = GetScreenWidth() - (left + width);
	if (diff < 0) then
		FXP_LevelAlert:SetPoint("BOTTOMRIGHT", FXP_XPExtraFillBar1Texture, "TOPRIGHT", diff+34, 16);
	end
	diff = GetScreenHeight() - (bottom + height);
	if (diff < 0) then
		FXP_LevelAlert:ClearAllPoints();
		FXP_LevelAlert:SetPoint("TOPRIGHT", FXP_XPExtraFillBar1Texture, "BOTTOMRIGHT", 34, -16);
		FXP_LevelAlert.ArrowUP:Hide();
		FXP_LevelAlert.ArrowGlowUP:Hide();		
		FXP_LevelAlert.ArrowDOWN:Show();
		FXP_LevelAlert.ArrowGlowDOWN:Show();
	else
		FXP_LevelAlert.ArrowUP:Show();
		FXP_LevelAlert.ArrowGlowUP:Show();		
		FXP_LevelAlert.ArrowDOWN:Hide();
		FXP_LevelAlert.ArrowGlowDOWN:Hide();
	end

	-- animate to show
	FXP_LevelAlert.showAnim:Play();
	FXP_LevelAlert:Show();
	
	PlaySound("UI_AutoQuestComplete");	-- same as auto quest complete popup
end

------------------------------------------------------
-- Config menu
------------------------------------------------------

function FXP_ShowMenu(self, button)
	if (button == "RightButton") then
		ToggleDropDownMenu(1, nil, FXP_MenuDropDown, "cursor", 0, 0, "TOP");
		PlaySound("igMainMenuOptionCheckBoxOn");
	end
end

function FXP_MenuDropDown_OnLoad(self)
	UIDropDownMenu_Initialize(self, FXP_MenuDropDown_Initialize, "MENU");
end

function FXP_MenuDropDown_Initialize(dropDown)
	
	local info;
			
	local titleText = GetAddOnMetadata(addonName, "Title");
	local version = GetAddOnMetadata(addonName, "Version");
	titleText = titleText .. " " .. version;
	info = UIDropDownMenu_CreateInfo();
	info.text = titleText;
	info.isTitle = true;
	info.notCheckable = 1;
	UIDropDownMenu_AddButton(info);

	info = UIDropDownMenu_CreateInfo();
	info.isNotRadio = true;
	info.text = FXP_OPTION_SHOW_INCOMPLETE;
	info.func = FXP_MenuClick;
	info.checked = FXP_Config.ShowIncomplete;
	info.value = "ShowIncomplete";
	info.keepShownOnClick = 1;
	UIDropDownMenu_AddButton(info);
	
	info = UIDropDownMenu_CreateInfo();
	info.isNotRadio = true;
	info.text = FXP_OPTION_LEVEL_ALERT;
	info.func = FXP_MenuClick;
	info.checked = FXP_Config.LevelAlert;
	info.value = "LevelAlert";
	info.keepShownOnClick = 1;
	UIDropDownMenu_AddButton(info);
	
end

function FXP_MenuClick(self)
	FXP_Config[self.value] = UIDropDownMenuButton_GetChecked(self);
	FXP_UpdateQuestXP();
	FXP_MainMenuExpBar_Update();
end

