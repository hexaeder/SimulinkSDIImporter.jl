module SimulinkSDIImporter

using CSV
using JSON3
using Dates
using TimeZones
using AbstractTrees

export read_json, read_data, show_sdi

MATLAB_EXEC = "matlab"
MATLAB_FLAGS = ["-nodisplay", "-batch"]
# Write your package code here.

# matlab -nodisplay -batch "x=3; disp(x)"

function show_structure(file)
end

function save_json(file)
    file = abspath(file)
    basedir = dirname(file)
    bn = basename(file)

    @assert isfile(file) "There is no file $file"

    @info "Launch matlab to export json..."
    matlabstr = "pwd(); addpath(\"$(@__DIR__)\"); fh=SDIFileHandler(\"$bn\");fh.save_json()"

    cmd = Cmd(`$MATLAB_EXEC $MATLAB_FLAGS "$matlabstr"`; dir=basedir)
    run(cmd)
end

function read_data(file, keys)
    file = abspath(file)
    basedir = dirname(file)
    bn = basename(file)

    tree = read_json(file)
    @assert isempty(children(tree[keys])) "Key Sequence $keys does not lead to leaf node/signal."

    csvfile = joinpath(basedir, _csv_name(file, keys))

    if !isfile(csvfile)
        @info "Launch matlab to export data..."
        matlabstr = "pwd(); addpath(\"$(@__DIR__)\"); fh=SDIFileHandler(\"$bn\"); fh.export_signal($(repr(keys)))"

        cmd = Cmd(`$MATLAB_EXEC $MATLAB_FLAGS "$matlabstr"`; dir=basedir)
        run(cmd)
    end
    @assert isfile(csvfile)

    if readline(csvfile) != _get_filedate(file)
        @warn "Timestamps do not match, $(basename(file)) was changed after the CSV was exported."
    end

    csv = CSV.File(csvfile; header=2)
    @info "Loaded columns: $(csv.names)"
    return csv
end

function show_sdi(file)
    file = abspath(file)
    basedir = dirname(file)
    bn = basename(file)

    @info "Launch matlab and open SDI..."
    matlabstr = "pwd(); addpath(\"$(@__DIR__)\"); fh=SDIFileHandler(\"$bn\"); fh.open_sdi()"

    cmd = Cmd(`$MATLAB_EXEC $MATLAB_FLAGS "$matlabstr"`; dir=basedir)
    run(cmd; wait=false)
end

function read_json(file)
    jsonf = file * ".json"
    if !isfile(jsonf)
        save_json(file)
    end

    jsonstr = read(jsonf, String)
    desc = JSON3.read(jsonstr)

    if desc.version !== _get_filedate(file)
        @warn "Timestamps do not match, $(basename(file)) was changed after the json was extracted."
    end
    SDIData(desc)
end

function _get_filedate(file)
    filedate = Dates.unix2datetime(mtime(file))
    zdt = ZonedDateTime(filedate, tz"UTC")
    zdt = astimezone(zdt, tz"Europe/Berlin")
    filedate = DateTime(zdt)
    Dates.format(filedate, dateformat"dd-u-YYYY HH:MM:SS")
end

export SDIData

struct SDIData
    x::String
    children::Vector{SDIData}
end
function SDIData(desc)
    children = [SDIData(c) for c in desc.content]
    SDIData(desc.name, children)
end
function SDIData(str::String)
    children = SDIData[]
    SDIData(str, children)
end

AbstractTrees.children(t::SDIData) = t.children;
AbstractTrees.nodevalue(t::SDIData) = t.x;

function Base.getindex(n::SDIData, key::String)
    matches = Set{Int}()
    map(enumerate(children(n))) do (i, child)
        name = nodevalue(child)
        startswith(name, key) && push!(matches, i)
    end
    if length(matches) > 1
        throw(ArgumentError("Key $key not specific enough: $(nodevalue.(children(n)[collect(matches)]))"))
    elseif isempty(matches)
        throw(ArgumentError("No match for key $key: $(nodevalue.(children(n)))"))
    end
    return children(n)[only(matches)]
end

function Base.getindex(n::SDIData, keys)
    for key in keys
        n = n[key]
    end
    n
end
Base.getindex(n::SDIData, keys...) = n[keys]

Base.show(io::IO, ::MIME"text/plain", n::SDIData) = print_tree(io, n)

function Base.haskey(n::SDIData, key)
    try
        n[key]
    catch
        return false
    end
    return true
end

function _reduce_key(n::SDIData, keys)
    @assert haskey(n, keys) "Keysequence $key not valid."
    shortkeys = String[]
    for key in keys[begin:end-1]
        for i in 0:length(key)
            short = key[1:i]
            if haskey(n, short)
                push!(shortkeys, short)
                break
            end
        end
        n = n[key]
    end
    push!(shortkeys, nodevalue(n[keys[end]]))
    return shortkeys
end

function _csv_name(file, keys)
    tree = read_json(file)
    tree[keys] # check if getindex works

    basen = basename(file)
    @assert endswith(basen, ".mldatx")
    basen = basen[1:end-length(".mldatx")]
    return basen * "_" * join(_reduce_key(tree, keys),"-") * ".csv"
end

end
