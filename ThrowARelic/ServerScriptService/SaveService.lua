--[[
	SaveService (ModuleScript)
	Emplacement : ServerScriptService/SaveService

	Lecture / écriture des données joueur dans un DataStore, avec réessais.
	Ne connaît PAS le format des données : GameServer lui passe une table
	déjà prête à être stockée (nombres, textes, tables simples).

	Si le DataStore est indisponible (place non publiée, ou "Enable Studio
	Access to API Services" décoché), le service passe en mode mémoire :
	le jeu fonctionne normalement mais rien n'est sauvegardé.
]]

local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local SaveService = {}

local store: DataStore? = nil
local disabledReason: string? = nil

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.DataStoreName)
	end)
	if ok then
		store = result
	else
		disabledReason = tostring(result)
	end
end

-- Erreurs qui ne passeront jamais en réessayant (accès Studio refusé, place non publiée)
local function isPermanentError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studio", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "api services", 1, true) ~= nil
end

local function disable(reason: string)
	if not disabledReason then
		disabledReason = reason
		warn("[SaveService] Sauvegarde DÉSACTIVÉE (mode mémoire) : " .. reason)
	end
end

-- Exécute `fn` avec réessais. Renvoie ok, résultat.
local function withRetries(label: string, fn: () -> any): (boolean, any)
	local lastError = nil
	for attempt = 1, Config.Save.Retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		warn(("[SaveService] %s : échec %d/%d : %s"):format(label, attempt, Config.Save.Retries, lastError))
		if isPermanentError(lastError) then
			disable(lastError)
			break
		end
		if attempt < Config.Save.Retries then
			task.wait(Config.Save.RetryDelay)
		end
	end
	return false, lastError
end

local function keyFor(userId: number): string
	return Config.Save.KeyPrefix .. tostring(userId)
end

function SaveService.IsEnabled(): boolean
	return store ~= nil and disabledReason == nil
end

function SaveService.GetDisabledReason(): string?
	return disabledReason
end

--[[
	Charge les données d'un joueur.
	Renvoie :
	  "ok", data      -> données trouvées (ou nil si nouveau joueur)
	  "disabled", nil -> mode mémoire : on joue sans sauvegarde
	  "failed", nil   -> erreur réseau : NE PAS sauvegarder ce joueur
	                     (on écraserait ses vraies données avec des données vides)
]]
function SaveService.Load(userId: number): (string, any)
	if not SaveService.IsEnabled() then
		return "disabled", nil
	end
	local ok, result = withRetries("Chargement " .. userId, function()
		return (store :: DataStore):GetAsync(keyFor(userId))
	end)
	if ok then
		return "ok", result
	end
	return SaveService.IsEnabled() and "failed" or "disabled", nil
end

-- Sauvegarde une table de données. Renvoie true si c'est écrit.
function SaveService.Save(userId: number, snapshot: { [string]: any }): boolean
	if not SaveService.IsEnabled() then
		return false
	end
	local ok = withRetries("Sauvegarde " .. userId, function()
		(store :: DataStore):UpdateAsync(keyFor(userId), function()
			return snapshot
		end)
	end)
	return ok
end

return SaveService
