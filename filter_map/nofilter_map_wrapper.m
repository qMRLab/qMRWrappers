% Simple wrapper for saving unfiltered B1plus maps
%
% Required inputs:
%
%    Image file names:
%        - b1plus_nii --> subID*.nii.gz (e.g. sub-01_B1plusmap.nii.gz)
%
% nofilter_map_wrapper(___,PARAM1, VAL1, PARAM2, VAL2,___)
%
% Parameters include:
%       
%   'qmrlab_path'       Absolute path to the qMRLab's root directory. (string)
% 
% Outputs: 
%
%    subID_B1plusmap_unfiltered.nii.gz       Filtered B1 plus map. 
%
%    subID_B1plusmap_unfiltered.json         Filtered B1 plus map metadata. 
%                                          
%    subIDun_filter_map_qmrlab.mat  Object containing qMRLab options. 
% 
% IMPORTANT:
%
%    FitResults.mat     Removed after fitting.
%
%    Subject ID         This wrapper assumes that the input data
%                       has a subject ID prefix before the first
%                       occurence of the '_' character.  
%
% Written by: Mathieu Boudreau, 2022
% GitHub:     @mathieuboudreau
%
% Intended use: qMRFlow 
% =========================================================================


function nofilter_map_wrapper(b1plus_nii,varargin)

    
    % This env var will be consumed by qMRLab
    setenv('ISNEXTFLOW','1');
    
    
    if nargin>1
        if any(cellfun(@isequal,varargin,repmat({'qmrlab_path'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'qmrlab_path'},size(varargin)))==1);
            qMRdir = varargin{idx+1};
        end
    end

    try
        disp('=============================');
        qMRLabVer;
    catch
        warning('Cant find qMRLab. Adding qMRLab_DIR to the path: ');
        if ~strcmp(qMRdir,'null')
            qmr_init(qMRdir);
        else
            error('Please set qMRLab_DIR parameter in the nextflow.config file.');
        end
        qMRLabVer;
    end
    
    data = struct();
    
    if nargin >1

        if any(cellfun(@isequal,varargin,repmat({'siemens'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'siemens'},size(varargin)))==1);
            issiemens = varargin{idx+1};
        else
            issiemens = 0;
        end
        
         if any(cellfun(@isequal,varargin,repmat({'sid'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'sid'},size(varargin)))==1);
            SID = varargin{idx+1};
         else
            SID = [];
        end

    end 
    
    data.Raw = double(load_nii_data(b1plus_nii));

    if issiemens
        data.Raw = data.Raw./800;
    end

    
    % ==== Save outputs ==== 
    disp('-----------------------------');
    disp('Saving unfiltered B1 map...');
    
    copyfile(b1plus_nii, 'Filtered.nii.gz')

    % ==== Rename outputs ==== 
    if ~isempty(SID)
        movefile('Filtered.nii.gz',[SID '_B1plusmap_unfiltered.nii.gz']);
    else
        movefile('Filtered.nii.gz',[SID 'B1plusmap_unfiltered.nii.gz']);
    end
    
    
    addField = struct();

    addField.BasedOn = {b1plus_nii};
        
    if ~isempty(SID)
        savejson('',addField,[pwd filesep SID '_B1plusmap_unfiltered.json']);
    else
        savejson('',addField,[pwd filesep 'B1plusmap_unfiltered.json']);
    end
 
    if ~isempty(SID)
    disp(['Success: ' SID]);
    disp('-----------------------------');
    disp('Saved: ');
    disp(['    ' SID '_B1plusmap_unfiltered.nii.gz']);
    disp(['    ' SID '_B1plusmap_unfiltered.json'])
    disp('=============================');
    end

    if moxunit_util_platform_is_octave
        warning('on','all');
    end
    
    
end
     
    
function qmr_init(qmrdir)

run([qmrdir filesep 'startup.m']);

end