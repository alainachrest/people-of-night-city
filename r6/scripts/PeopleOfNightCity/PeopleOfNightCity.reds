// People of Night City: the game-side helpers the CET mod calls.
//
//  - WalkNPC: sends an NPC walking (or running) to a point the game's own way,
//    planning a path on the navmesh, as the game's own move commands do.
//  - Scanner names: the people the mod spawns show their own name (and who
//    they're with) when V scans them.

module PeopleOfNightCity

public class PoNCSystem extends ScriptableSystem {
    // the move each NPC was last told to make (so a new one replaces it)
    private let m_moveIDs: array<EntityID>;
    private let m_moveCmds: array<ref<AIMoveToCommand>>;

    // what the scanner calls the NPCs the mod spawned
    private let m_scanIDs: array<EntityID>;
    private let m_scanNames: array<String>;
    private let m_scanFactions: array<String>;

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
