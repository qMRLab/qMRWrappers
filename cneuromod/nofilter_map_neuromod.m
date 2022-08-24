% Simple wrapper for filtering B1plus maps
%
% Required inputs:
%
%    Image file names:
%        - b1plus_nii --> subID*.nii.gz (e.g. sub-01_B1plusmap.nii.gz)
%
% filter_map_wrapper(___,PARAM1, VAL1, PARAM2, VAL2,___)
%
% Parameters include:
%
%   'mask'              File name for the (.nii.gz formatted)
%                       binary mask. (stiring)
%
%   'siemens'           Indicates whether the raw B1map is acquired using 
%                       Siemens TFL B1map sequence. If so, the map 
%                       will be divided by 800. (boolean)
%
%   'type'              Type of filter (string)
%                           - 'gaussian'
%                           - 'median'
%                           - 'spline'
%                           - 'polynomial'
%
%   'dimension'         In which dimensions to apply the filter (string)
%                           - '2D'
%                           - '3D'
%
%   'order'             Depends on the type selection (integer)
%                           - For type polynomial, it is the order of the polynomial.
%                           - For type spline, it is the 'amount of smoothness'
%
%   'size'              Extent of filter in number of voxels (x y z) (vector)
%                           - For type gaussian, it is FWHM.
%                           - For type median, it is number of voxels.
%       
%   'qmrlab_path'       Absolute path to the qMRLab's root directory. (string)
% 
% Outputs: 
%
%    subID_B1plusmap_filtered.nii.gz       Filtered B1 plus map. 
%
%    subID_B1plusmap_filtered.json         Filtered B1 plus map metadata. 
%                                          
%    subID_filter_map_qmrlab.mat  Object containing qMRLab options. 
% 
% IMPORTANT:
%
%    FitResults.mat     Removed after fitting.
%
%    Subject ID         This wrapper assumes that the input data
%                       has a subject ID prefix before the first
%                       occurence of the '_' character.  
%
% Written by: Agah Karakuzu, 2020
% GitHub:     @agahkarakuzu
%
% Intended use: qMRFlow 
% =========================================================================


function nofilter_map_neuromod(SID,b1plus_nii,varargin)

    disp('Runnning filtermap neuromod latest');

    if moxunit_util_platform_is_octave
       warning('off','all');
    end
    
    validDir = @(x) exist(x,'dir');
    
    keyval = regexp(SID,'[^-_]*','match');
    
    p = inputParser();
    
    %Input parameters conditions
    validNii = @(x) exist(x,'file') && strcmp(x(end-5:end),'nii.gz');
    
    addParameter(p,'siemens',false,@islogical);
    addParameter(p,'qmrlab_path',[],@ischar);
    addParameter(p,'sesFolder',false,@islogical);
    addParameter(p,'targetDir',[],validDir);
    
    parse(p,varargin{:});
    
    % Capture session folder flag
    sesFolder = p.Results.sesFolder; 

    if ismember('ses',keyval)
        [~,idx]= ismember('ses',keyval);
        sesVal = keyval{idx+1};
    else
       sesVal = [];
    end
    
    if ismember('sub',keyval)
        [~,idx]= ismember('sub',keyval);
        subVal = keyval{idx+1};
    else
       subVal = SID;
    end
    
    % This env var will be consumed by qMRLab
    setenv('ISNEXTFLOW','1');
    setenv('ISBIDS','1');

    if ~isempty(p.Results.qmrlab_path); qMRdir = p.Results.qmrlab_path; end

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
    
    if ~isempty(p.Results.siemens); issiemens = p.Results.siemens; end
    
    data = load_untouch_nii(b1plus_nii);
    data.img = double(load_nii_data(b1plus_nii));

    % TODO: 
    % Check if Octave is OK with inputParser (and MATLAB version range)
    % If so use it to reduce the verbosity below.

    if issiemens
        data.img = data.img./800;
    % ISBIDS is set to 1, FitData will expect
    % inputs to be in relative % (see input_BIDS_units.json)
    % therefore, we need to multiply it by 100 here
    data.img = data.img.*100;
    end

    nii = nii_reset_orient(data.hdr, data.img);
    data.hdr = nii.hdr;
    data.img = nii.img;

    
    % ==== Save Data ====
    
    addField = struct();

    addField.BasedOn = {b1plus_nii};
    if ~isempty(SID)
        savejson('',addField,[pwd filesep SID '_B1plusmap_unfiltered.json']);
        save_untouch_nii(data, [pwd filesep SID '_B1plusmap_unfiltered.nii.gz'])
    else
        savejson('',addField,[pwd filesep 'B1plusmap_unfiltered.json']);
        save_untouch_nii(data, [pwd filesep 'B1plusmap_unfiltered.nii.gz'])
    end
        
    if moxunit_util_platform_is_octave
        warning('on','all');
    end
    
    setenv('ISBIDS','');
    setenv('ISNEXTFLOW','');

end
     
    
function qmr_init(qmrdir)

run([qmrdir filesep 'startup.m']);

end