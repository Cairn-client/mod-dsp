namespace NebulaModel.Packets.Factory;

public class KillEntityRequest
{
    public KillEntityRequest() { }

    public KillEntityRequest(int planetId, int objId, bool spawnPrebuild)
    {
        PlanetId = planetId;
        ObjId = objId;
        SpawnPrebuild = spawnPrebuild;
    }

    public int PlanetId { get; set; }
    public int ObjId { get; set; }
    public bool SpawnPrebuild { get; set; }
}
