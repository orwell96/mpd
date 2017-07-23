
mpd={}

--config
mpd.pause_between_songs=30

--end config

mpd.modpath=minetest.get_modpath("mpd")
if not mpd.modpath then
	error("mpd mod folder has to be named 'mpd'!")
end
--{name, length, gain~1}
mpd.songs = {}
mpd.randomized = {}
local sfile, sfileerr=io.open(mpd.modpath.."/songs.txt")
if not sfile then error("Error opening songs.txt: "..sfileerr) end
for line in sfile:lines() do
	if line~="" and string.sub(line, 1, 1)~="#" then
		local name, timeMinsStr, timeSecsStr, gainStr = string.match(line, "^(%S+)%s+(%d+):([%d%.]+)%s+([%d%.]+)$")
		local timeMins, timeSecs, gain = tonumber(timeMinsStr), tonumber(timeSecsStr), tonumber(gainStr)
		if name and timeMins and timeSecs and gain then
			mpd.songs[#mpd.songs+1]={name=name, length=timeMins*60+timeSecs, lengthhr=timeMinsStr..":"..timeSecsStr, gain=gain}
		else
			minetest.log("warning", "[mpd] Misformatted song entry in songs.txt: "..line)
		end
	end
end
sfile:close()

if #mpd.songs==0 then
	print("[mpd]no songs registered, not doing anything")
	return
end

mpd.storage = minetest.get_mod_storage()

mpd.handles={}

mpd.playing=false
mpd.id_playing=nil
mpd.song_time_left=nil
mpd.time_next=10 --sekunden
mpd.id_last_played=nil

minetest.register_globalstep(function(dtime)
	if mpd.playing then
		if mpd.song_time_left<=0 then
			mpd.stop_song()
			mpd.time_next=mpd.pause_between_songs
		else
			mpd.song_time_left=mpd.song_time_left-dtime
		end
	elseif mpd.time_next then
		if mpd.time_next<=0 then
			mpd.next_song()
		else
			mpd.time_next=mpd.time_next-dtime
		end
	end
end)
mpd.play_song=function(id)
	if mpd.playing then
		mpd.stop_song()
	end
	local song=mpd.songs[id]
	if not song then return end
	for _,player in ipairs(minetest.get_connected_players()) do
		local pname=player:get_player_name()
		local pvolume=tonumber(mpd.storage:get_string("vol_"..pname))
		if not pvolume then pvolume=1 end
		if pvolume>0 then
			local handle = minetest.sound_play(song.name, {to_player=pname, gain=song.gain*pvolume})
			if handle then
				mpd.handles[pname]=handle
			end
		end
	end
	mpd.playing=id
	--adding 2 seconds as security
	mpd.song_time_left = song.length + 2
end
mpd.stop_song=function()
	for pname, handle in pairs(mpd.handles) do
		minetest.sound_stop(handle)
	end
	mpd.id_last_played=mpd.playing
	mpd.playing=nil
	mpd.handles={}
	mpd.time_next=nil
end

mpd.next_song=function()
	local next
	-- create new list if no songs are in randomized list
	if #mpd.randomized == 0 then
		minetest.log("info", "[mpd] Creating randomized playlist")
		local nums = {}
		local entry = 0
		for i=1, #mpd.songs do
			-- add all songs except last one played to temporary list
			if mpd.id_last_played ~= i then
				nums[i]=i
			end
		end
		-- randomize temporary list and save as randomized
		repeat
			entry = table.remove(nums, math.random(1,#nums))
			table.insert(mpd.randomized, entry)
		until #nums == 0
		minetest.log("info", "[mpd] ...done")
	end
	-- extract next song to be played
	next=table.remove(mpd.randomized)
	mpd.play_song(next)
end

mpd.song_human_readable=function(id)
	local song=mpd.songs[id]
	return id..": "..song.name.." ["..song.lengthhr.."]"
end

minetest.register_privilege("mpd", "may control the music player daemon (mpd) mod")

minetest.register_chatcommand("mpd_stop", {
	params = "",
	description = "Stop the song currently playing",
	privs = {mpd=true},
	func = function(name, param)
		mpd.stop_song()
	end,		
})
minetest.register_chatcommand("mpd_list", {
	params = "",
	description = "List all available songs and their IDs",
	privs = {mpd=true},
	func = function(name, param)
		for k,v in ipairs(mpd.songs) do
			minetest.chat_send_player(name, mpd.song_human_readable(k))
		end
	end,		
})
minetest.register_chatcommand("mpd_play", {
	params = "<id>",
	description = "Play the songs with the given ID (see ids with /mpd_list)",
	privs = {mpd=true},
	func = function(name, param)
		id=tonumber(param)
		if id and id>0 and id<=#mpd.songs then
			mpd.play_song(id)
			return true,"Playing: "..mpd.song_human_readable(id)
		end
		return false, "Invalid song ID!"
	end,		
})
minetest.register_chatcommand("mpd_what", {
	params = "",
	description = "Display the currently played song.",
	privs = {mpd=true},
	func = function(name, param)
	if not mpd.playing then return true,"Nothing playing, "..math.floor(mpd.time_next or 0).." sec. left until next song." end
	return true,"Playing: "..mpd.song_human_readable(mpd.playing).."\nTime Left: "..math.floor(mpd.song_time_left or 0).." sec."
end,		
})
minetest.register_chatcommand("mpd_next", {
	params = "[seconds]",
	description = "Start the next song, either immediately (no parameters) or after n seconds.",
	privs = {mpd=true},
	func = function(name, param)
		mpd.stop_song()
		if param and tonumber(param) then
			mpd.time_next=tonumber(param)
			return true,"Next song in "..param.." seconds!"
		else
			mpd.next_song()
			return true,"Next song started!"
		end
	end,		
})
minetest.register_chatcommand("mvolume", {
	params = "[volume level (0-1)]",
	description = "Set your background music volume. Use /mvolume 0 to turn off background music for you. Without parameters, show your current setting.",
	privs = {},
	func = function(pname, param)
		if not param or param=="" then
			local pvolume=tonumber(mpd.storage:get_string("vol_"..pname))
			if not pvolume then pvolume=1 end
			if pvolume>0 then
				return true, "Your music volume is set to "..pvolume.."."
			else
				if mpd.handles[pname] then
					minetest.sound_stop(mpd.handles[pname])
				end
				return true, "Background music is disabled for you. Use '/mvolume 1' to enable it again."
			end
		end
		local pvolume=tonumber(param)
		if not pvolume then
			return false, "Invalid usage: /mvol [volume level (0-1)]"
		end
		pvolume = math.min(pvolume, 1)
		pvolume = math.max(pvolume, 0)
		mpd.storage:set_string("vol_"..pname, pvolume)
		if pvolume>0 then
			return true, "Music volume set to "..pvolume..". Change will take effect when the next song starts."
		else
			if mpd.handles[pname] then
				minetest.sound_stop(mpd.handles[pname])
			end
			return true, "Disabled background music for you. Use /mvol to enable it again."
		end
	end,		
})
