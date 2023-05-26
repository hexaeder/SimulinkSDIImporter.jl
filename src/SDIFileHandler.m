classdef SDIFileHandler < handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here

    properties
        file
        loaded_to_sdi
        runds
    end

    methods
        function obj = SDIFileHandler(file)
            %UNTITLED Construct an instance of this class
            %   Detailed explanation goes here
            obj.file = file;
            obj.loaded_to_sdi = false;
            obj.runds = Simulink.SimulationData.Dataset();
        end

        function load_file(obj)
            if obj.loaded_to_sdi == false
                disp("Load "+obj.file+" to SDI.")
                Simulink.sdi.clear();
                Simulink.sdi.load(obj.file);
                obj.loaded_to_sdi = true;
            end
        end

        function save_json(obj)
            if obj.has_json() && obj.json_updated()
                disp("JSON is up to date.")
                return
            elseif obj.has_json()
                disp("JSON is outdated, recreate.")
            else
                disp("No JSON found, create.")
            end
            desc = obj.describe_sdifile();
            json = jsonencode(desc, PrettyPrint=true);
            fid = fopen(obj.file+".json",'wt');
            fprintf(fid, json);
            fclose(fid);
        end

        function ret = has_json(obj)
            fname = obj.file+".json";
            ret = isfile(fname);
        end

        function ret = json_updated(obj)
            assert(obj.has_json())
            desc = obj.load_json_unsafe();
            if desc.version == dir(obj.file).date
                ret = true;
            else
                ret = false;
            end
        end

        function desc = load_json_unsafe(obj)
            fname = obj.file+".json";
            fid = fopen(fname);
            raw = fread(fid,inf);
            str = char(raw');
            fclose(fid);
            desc = jsondecode(str);
        end

        function desc = load_json(obj)
            if obj.has_json() && obj.json_updated()
                % do nothing
            elseif obj.has_json()
                disp("JSON is outdated, recreate.")
                obj.save_json()
            else
                disp("No JSON found, create.")
                obj.save_json()
            end
            desc = obj.load_json_unsafe();
        end

        function desc = describe_sdifile(obj)
            obj.load_file()
            desc.name = obj.file;
            desc.type = "SDI Savefile (.mldatx)";
            desc.version = dir(obj.file).date;
            desc.content = {};
            runids = Simulink.sdi.getAllRunIDs();
            for runid = runids'
                run = Simulink.sdi.getRun(runid);
                obj.runds = export(run);
%                 r.name = run.name;
%                 r.type = class(run);
%                 r.content = obj.describe_dataset(export(run));
                desc.content{end+1} = obj.describe_dataset(obj.runds);
            end
        end

        function desc = describe_dataset(obj, ds)
            desc.name = ds.Name;
            desc.type = class(ds);
            elnames = getElementNames(ds);
            desc.content = {};
            for i = 1:length(elnames)
                elname = elnames{i};
                element = ds.getElement(elname);
                %disp(element)
                if isa(element, 'Simulink.SimulationData.Signal')
                    %disp("add signal"+elname)
                    desc.content{end+1} = element.Name;
                elseif isa(element, 'Simulink.SimulationData.Dataset')
                    %disp("recursive go down"+elname)
                    %disp(element);
                    desc.content{end+1} = obj.describe_dataset(element);
                else
                    error("Cannot handle element of type"+class(element))
                end
            end
        end

        %% export data functionality
        function ds = load_run(obj, namepart)
            desc = descent(obj.load_json(), namepart);
            name = desc.name;
            if strcmp(obj.runds.Name, name)
                % allready loaded
                ds = obj.runds;
            else
                % load from file
                obj.load_file()
                runids = Simulink.sdi.getAllRunIDs();
                for runid = runids'
                    run = Simulink.sdi.getRun(runid);
                    if strcmp(run.name, name)
                        disp("Export " +name+" to workspace.")
                        ds = export(run);
                        obj.runds = ds;
                        return
                    end
                end
                error("Could not find run "+name+" in "+obj.file)
            end
            obj.runds = ds;
        end

        function export_signal(obj, id)
            desc = obj.load_json();
            namechain = string.empty();
            for part = id
                if part == id(end)
                    [fn, ~] = fullname(part, desc.content);
                    namechain(end+1) = fn;
                else
                    for p = 0:strlength(part)
                        short = extractBefore(part, p+1);
                        try
                            desc = descent(desc, short);
                        catch
                            continue
                        end
                        namechain(end+1) = short;
                        break
                    end
                end
            end
            fname = extractBefore(obj.file, ".mldatx")+"_"+join(namechain, '-')+".csv";

            if isfile(fname)
                fid = fopen(fname,'r');
                str = fgetl(fid);
                fclose(fid);
                if strcmp(str, obj.load_json().version)
                    disp("Data allready exported to file.")
                    return
                else
                    disp("Timestamps do no match, reexport.")
                end
            end
            disp("Export Data to "+fname)
            
            % load file
            ds = obj.load_run(namechain(1));
            desc = descent(obj.load_json(), ds.Name);
            for part = namechain(2:end)
                desc = descent(desc, part);
                ds = ds.getElement(to_name(desc));
            end

            % write to file
            fid = fopen(fname,'wt');
            fprintf(fid, obj.load_json().version+"\n");
            fclose(fid);
            
            if isstruct(ds.Values)
                tss = timeseries.empty();
                fields = fieldnames(ds.Values);
                for f = fields'
                    tss(end+1) = ds.Values.(string(f));
                end
                tt = timeseries2timetable(tss);
            else
                tt = timeseries2timetable(ds.Values);
            end

            t = timetable2table(tt);
            t.Time = seconds(t.Time);
            writetable(t, fname,'WriteMode','Append','WriteVariableNames',true);
            %writetable(t, fname,'WriteVariableNames',true);
        end
    end
end

function [fn, idx] = fullname(namepart, content)
    allnames = string.empty();
    for i = 1:length(content)
        el = content(i);
        allnames(i) = to_name(el);    
    end
    
    matches = [];
    for i = 1:length(allnames)
        if startsWith(allnames(i), namepart)
            matches(end+1) = i;
        end
    end
    if length(matches) > 1
        error("Cannot uniquly resolve "+namepart)
    elseif isempty(matches)
        error("No matching element for name "+namepart)
    end
    idx = matches(1);
    fn = allnames(idx);
end

function ret = descent(desc, namepart)
    [fn, idx] = fullname(namepart, desc.content);
    if ~strcmp(namepart, fn)
        %disp("Resolved '"+namepart+ "' to '"+fn+"'")
    end
    ret = desc.content(idx);
end

function name = to_name(el)
if iscell(el) && length(el)==1
    name = string(el);
elseif isa(el, "struct")
    name = el.name;
else
    error("Don't know the name of"+el)
end
end

