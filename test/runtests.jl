using SimulinkSDIImporter
using Test

@testset "SimulinkSDIImporter.jl" begin
    using SimulinkSDIImporter: save_json, read_json, _reduce_key, _csv_name, read_data

    file = "../assets/setpoint_steps.mldatx"
    @time _save_json(file)

    desc = _read_json(file)

    desc.content[1].content[1].content[1]

    tree = SDIData(desc)
    print_tree(tree)

    tree["Voltage "]["Run 1"]["A_"]
    tree["Voltage", "Run 1", "A_"]




    haskey(tree, ["Voltage", "Run 1", "A_"])

    _reduce_key(tree, ["Voltage", "Run 1", "A_"])

    length("foo")
    "foo"[1:3]

    print_tree(tree)

    keys = ["Synced V", "Run 1", "U_INV_dq"]
    @time dq = read_data(file, keys);

    keys = ["Synced V", "Run 1", "U_INV_ref"]
    @time ref = read_data(file, keys);

    read_json(file)["Synced V", "Run 1"]

    plot(dq.Time, dq.d)
    plot!(dq.Time, ref.d)

end
