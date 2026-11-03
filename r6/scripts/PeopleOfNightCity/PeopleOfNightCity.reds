// People of Night City: the game-side helpers the CET mod calls.
//
//  - WalkNPC: sends an NPC walking (or running) to a point the game's own way,
//    planning a path on the navmesh, as the game's own move commands do.
//  - Scanner names: the people the mod spawns show their own name (and who
//    they're with) when V scans them.
//  - Things in hand: people carry a phone, tablet, bag, can or cigarette, or
//    an umbrella when it rains, if their body has the walk for it.

module PeopleOfNightCity

// Keeps PoNCSystem up to date with how hard it's raining.
public class PoNCWeatherListener extends WeatherScriptListener {
    private let m_system: wref<PoNCSystem>;

    public func Init(system: ref<PoNCSystem>) {
        this.m_system = system;
    }

    public func OnRainIntensityChanged(rainIntensity: Float) {
        if IsDefined(this.m_system) {
            this.m_system.SetRain(rainIntensity);
        }
    }
}

public class PoNCSystem extends ScriptableSystem {
    // the move each NPC was last told to make (so a new one replaces it)
    private let m_moveIDs: array<EntityID>;
    private let m_moveCmds: array<ref<AIMoveToCommand>>;

    // what the scanner calls the NPCs the mod spawned
    private let m_scanIDs: array<EntityID>;
    private let m_scanNames: array<String>;
    private let m_scanFactions: array<String>;

    private let m_rain: Float;
    private let m_weather: ref<PoNCWeatherListener>;
    private let m_weatherID: Uint32;

    private func OnAttach() {
        this.m_weather = new PoNCWeatherListener();
        this.m_weather.Init(this);
        this.m_weatherID = GameInstance.GetWeatherSystem(GetGameInstance()).RegisterWeatherListener(this.m_weather);
    }

    private func OnDetach() {
        GameInstance.GetWeatherSystem(GetGameInstance()).UnregisterWeatherListener(this.m_weatherID);
        this.m_weather = null;
    }

    public func SetRain(intensity: Float) {
        this.m_rain = intensity;
    }

    public func Rain() -> Float {
        return this.m_rain;
    }

    public static func Get() -> ref<PoNCSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(n"PeopleOfNightCity.PoNCSystem") as PoNCSystem;
    }

    private func MoveSlot(id: EntityID) -> Int32 {
        let i = 0;
        while i < ArraySize(this.m_moveIDs) {
            if Equals(this.m_moveIDs[i], id) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    // Walks (run = true: runs) an NPC to a point, on the navmesh. False if it
    // can't take the order.
    public func WalkNPC(id: EntityID, x: Float, y: Float, z: Float, run: Bool) -> Bool {
        let puppet = GameInstance.FindEntityByID(GetGameInstance(), id) as ScriptedPuppet;
        if !IsDefined(puppet) {
            return false;
        }
        let ai = puppet.GetAIControllerComponent();
        if !IsDefined(ai) {
            return false;
        }
        let slot = this.MoveSlot(id);
        if slot >= 0 && IsDefined(this.m_moveCmds[slot]) {
            ai.CancelCommand(this.m_moveCmds[slot]);
        }
        let target: WorldPosition;
        WorldPosition.SetVector4(target, Vector4(x, y, z, 1.0));
        let spec: AIPositionSpec;
        AIPositionSpec.SetWorldPosition(spec, target);
        let cmd = new AIMoveToCommand();
        cmd.movementTarget = spec;
        cmd.movementType = run ? moveMovementType.Run : moveMovementType.Walk;
        cmd.ignoreNavigation = false;
        cmd.useStart = true;
        cmd.useStop = true;
        cmd.desiredDistanceFromTarget = 0.8;
        cmd.finishWhenDestinationReached = true;
        cmd.ignoreInCombat = true;
        if slot >= 0 {
            this.m_moveCmds[slot] = cmd;
        } else {
            ArrayPush(this.m_moveIDs, id);
            ArrayPush(this.m_moveCmds, cmd);
        }
        return ai.SendCommand(cmd);
    }

    // The state of the NPC's last move: 0 NotExecuting, 1 Enqueued, 2 Executing,
    // 3 Cancelled, 4 Interrupted, 5 Success, 6 Failure; -1 if it has none.
    public func MoveState(id: EntityID) -> Int32 {
        let slot = this.MoveSlot(id);
        if slot < 0 || !IsDefined(this.m_moveCmds[slot]) {
            return -1;
        }
        let puppet = GameInstance.FindEntityByID(GetGameInstance(), id) as ScriptedPuppet;
        if !IsDefined(puppet) {
            return -1;
        }
        let ai = puppet.GetAIControllerComponent();
        if !IsDefined(ai) {
            return -1;
        }
        return EnumInt(ai.GetCommandState(this.m_moveCmds[slot]));
    }

    // Forgets everything about an NPC (it was despawned).
    public func Forget(id: EntityID) {
        let slot = this.MoveSlot(id);
        if slot >= 0 {
            ArrayErase(this.m_moveIDs, slot);
            ArrayErase(this.m_moveCmds, slot);
        }
        this.ClearScannerName(id);
    }

    public func SetScannerName(id: EntityID, name: String, faction: String) {
        let i = this.FindScannerName(id);
        if i >= 0 {
            this.m_scanNames[i] = name;
            this.m_scanFactions[i] = faction;
            return;
        }
        ArrayPush(this.m_scanIDs, id);
        ArrayPush(this.m_scanNames, name);
        ArrayPush(this.m_scanFactions, faction);
        while ArraySize(this.m_scanIDs) > 128 {
            ArrayErase(this.m_scanIDs, 0);
            ArrayErase(this.m_scanNames, 0);
            ArrayErase(this.m_scanFactions, 0);
        }
    }

    public func ClearScannerName(id: EntityID) {
        let i = this.FindScannerName(id);
        if i >= 0 {
            ArrayErase(this.m_scanIDs, i);
            ArrayErase(this.m_scanNames, i);
            ArrayErase(this.m_scanFactions, i);
        }
    }

    public func FindScannerName(id: EntityID) -> Int32 {
        let i = 0;
        while i < ArraySize(this.m_scanIDs) {
            if Equals(this.m_scanIDs[i], id) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    // Navmesh --------------------------------------------------------------

    // Is there navmesh (for people) at this point, within `tolerance` metres?
    public func OnNavmesh(x: Float, y: Float, z: Float, tolerance: Float) -> Bool {
        let player = GameInstance.GetPlayerSystem(GetGameInstance()).GetLocalPlayerControlledGameObject();
        let nav = GameInstance.GetAINavigationSystem(GetGameInstance());
        if !IsDefined(nav) || !IsDefined(player) {
            return false;
        }
        return nav.IsPointOnNavmesh(player, Vector4(x, y, z, 1.0), tolerance);
    }

    // A point on the navmesh (for people) within `radius` of a point; W is 0
    // if there's none.
    public func NavPoint(x: Float, y: Float, z: Float, radius: Float) -> Vector4 {
        let nav = GameInstance.GetAINavigationSystem(GetGameInstance());
        if !IsDefined(nav) {
            return Vector4(0.0, 0.0, 0.0, 0.0);
        }
        let res = nav.FindPointInSphereOnlyHumanNavmesh(Vector4(x, y, z, 1.0), radius, NavGenAgentSize.Human, false);
        if Equals(res.status, worldNavigationRequestStatus.OK) {
            return Vector4(res.point.X, res.point.Y, res.point.Z, 1.0);
        }
        return Vector4(0.0, 0.0, 0.0, 0.0);
    }

    // Things in hand ------------------------------------------------------

    // What someone can carry, by the walk it goes with, given the weather:
    // dry, anything; light rain, an umbrella, a bag or a phone; heavier rain,
    // an umbrella or a bag; a downpour, an umbrella.
    private func Allowed(walk: CName) -> Bool {
        let rain = this.m_rain;
        let phone = Equals(walk, n"TabletLocomotion") || Equals(walk, n"CellphoneLocomotion") || Equals(walk, n"CellphoneTalkingLocomotion");
        let bag = Equals(walk, n"PurseLocomotion") || Equals(walk, n"DufflebagLocomotion") || Equals(walk, n"LaptopbagLocomotion");
        let umbrella = Equals(walk, n"UmbrellaLocomotion");
        let other = Equals(walk, n"CanLocomotion") || Equals(walk, n"CigaretteLocomotion");
        if rain <= 0.01 {
            return phone || bag || other;
        }
        if rain < 0.5 {
            return umbrella || bag || phone;
        }
        if rain < 0.92 {
            return umbrella || bag;
        }
        return umbrella;
    }

    private func ItemFor(walk: CName, pick: Int32) -> String {
        if Equals(walk, n"TabletLocomotion") { return "Items.locomotion_crowd_tablet_d_neo_kistch"; }
        if Equals(walk, n"CellphoneLocomotion") { return "Items.locomotion_crowd_cellphone"; }
        if Equals(walk, n"CellphoneTalkingLocomotion") { return "Items.crowd_talking_cellphone"; }
        if Equals(walk, n"PurseLocomotion") { return "Items.locomotion_crowd_purse"; }
        if Equals(walk, n"DufflebagLocomotion") { return "Items.locomotion_crowd_duffle_bag"; }
        if Equals(walk, n"LaptopbagLocomotion") { return "Items.locomotion_crowd_laptop_bag"; }
        if Equals(walk, n"CigaretteLocomotion") { return "Items.locomotion_crowd_cigarette_i_stick"; }
        if Equals(walk, n"UmbrellaLocomotion") { return "Items.locomotion_crowd_int_apparel_002__umbrella_small"; }
        if Equals(walk, n"CanLocomotion") {
            let cans = ["Items.locomotion_crowd_soda_can_a", "Items.locomotion_crowd_soda_can_b", "Items.locomotion_crowd_soda_can_c", "Items.locomotion_crowd_bottle_e_beer"];
            return cans[pick % ArraySize(cans)];
        }
        return "";
    }

    // The look of the item (its colours), for the items that have several.
    private func LookFor(walk: CName, pick: Int32) -> CName {
        let n: Int32;
        if Equals(walk, n"CellphoneLocomotion") {
            n = pick % 6;
            return StringToName("int_accessories_cellphone_" + IntToString(n));
        }
        if Equals(walk, n"TabletLocomotion") {
            n = pick % 8;
            return StringToName("int_electronics_001__tablet_d_neo_kistch_item_appearance_" + IntToString(n));
        }
        if Equals(walk, n"PurseLocomotion") {
            n = pick % 5;
            return StringToName("int_accessories_001__purse_item_appearance_" + IntToString(n));
        }
        if Equals(walk, n"DufflebagLocomotion") {
            n = pick % 5;
            return StringToName("int_accessories_001__duffel_bag_item_appearance_" + IntToString(n));
        }
        return n"";
    }

    // Puts something in an NPC's hand: one of the things its body has a walk
    // for, allowed in this weather. `pick` (from the person) picks which, so
    // the same person carries the same thing in the same weather. 8 in 10
    // people carry something. Returns the item, or "" for nothing.
    public func GiveCarryItem(id: EntityID, pick: Int32) -> String {
        let puppet = GameInstance.FindEntityByID(GetGameInstance(), id) as ScriptedPuppet;
        if !IsDefined(puppet) {
            return "";
        }
        if pick % 10 >= 8 {
            return "";
        }
        let game = puppet.GetGame();
        if GameInstance.GetWorkspotSystem(game).IsActorInWorkspot(puppet) {
            return "";
        }
        let walks: array<CName>;
        for comp in puppet.GetComponents() {
            let anims = comp as entAnimationSetupExtensionComponent;
            if IsDefined(anims) {
                for entry in anims.animations.gameplay {
                    for name in entry.variableNames {
                        if this.Allowed(name) && !ArrayContains(walks, name) {
                            ArrayPush(walks, name);
                        }
                    }
                }
            }
        }
        if ArraySize(walks) == 0 {
            return "";
        }
        let walk = walks[(pick / 10) % ArraySize(walks)];
        let name = this.ItemFor(walk, pick / 100);
        if StrLen(name) == 0 {
            return "";
        }
        let item = ItemID.FromTDBID(TDBID.Create(name));
        let ts = GameInstance.GetTransactionSystem(game);
        if !ts.HasItem(puppet, item) && !ts.GiveItem(puppet, item, 1) {
            return "";
        }
        let slot = (pick / 1000) % 10 < 9 ? t"AttachmentSlots.WeaponRight" : t"AttachmentSlots.WeaponLeft";
        if !ts.AddItemToSlot(puppet, slot, item, true) {
            return "";
        }
        let look = this.LookFor(walk, pick / 100);
        if NotEquals(look, n"") {
            ts.ChangeItemAppearanceByName(puppet, item, look);
        }
        return name;
    }

    public func ScannerNameAt(i: Int32) -> String { return this.m_scanNames[i]; }
    public func ScannerFactionAt(i: Int32) -> String { return this.m_scanFactions[i]; }
}

// Scanning one of the mod's people shows their name and affiliation.
@wrapMethod(NPCPuppet)
public const func CompileScannerChunks() -> Bool {
    let ok = wrappedMethod();
    if !ok {
        return ok;
    }
    let system = PoNCSystem.Get();
    if !IsDefined(system) {
        return ok;
    }
    let i = system.FindScannerName(this.GetEntityID());
    if i < 0 {
        return ok;
    }
    let board = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().UI_ScannerModules);
    if !IsDefined(board) {
        return ok;
    }
    let name = new ScannerName();
    name.Set(system.ScannerNameAt(i));
    board.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerName, ToVariant(name));
    let faction = system.ScannerFactionAt(i);
    if StrLen(faction) > 0 {
        let chunk = new ScannerFaction();
        chunk.Set(faction);
        board.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerFaction, ToVariant(chunk));
    }
    return ok;
}
