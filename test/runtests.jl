using SimulinkSDIImporter
using Test

@testset "SimulinkSDIImporter.jl" begin
    using SimulinkSDIImporter: save_json, read_json, _reduce_key, _csv_name, read_data, _expand_key

    file = "../assets/setpoint_steps.mldatx"

    @time save_json(file)

    tree = read_json(file)

    @test tree["Voltage "]["Run 1"]["A_"] == tree["Voltage", "Run 1", "A_"]

    @test haskey(tree, [r"^Voltage", "Run 1", "A_"])

    @test _reduce_key(tree, [r"^Voltage", "Run 1", "A_"]) == ["V", "Run 1", "A_ref_DC"]

    keys = ["Synced V", "Run 1", "U_INV_dq"]
    @time dq = read_data(file, keys);

    keys = ["Synced V", "Run 1", "U_INV_ref"]
    @time ref = read_data(file, keys);

    read_json(file)["Synced V", "Run 1"]

    show_sdi(file)

    let edir = SimulinkSDIImporter._export_dir(file)
        @assert endswith(edir, ".export")
        rm(edir, recursive=true)
    end

    show_sdi(file)

    read_data(file, ["Voltage", "Run 1", "A_ref_DC"])
    read_data(file, ["Voltage", "Run 1", "U_INV_dq"])

    show_structure(file)
end
