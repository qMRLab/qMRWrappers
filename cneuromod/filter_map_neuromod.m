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


function filter_map_neuromod(SID,b1plus_nii,varargin)

    disp('Runnning mtsat neuromod latest');

    if moxunit_util_platform_is_octave
       warning('off','all');
    end
    
    validDir = @(x) exist(x,'dir');
    
    keyval = regexp(SID,'[^-_]*','match');
    
    p = inputParser();
    addParameter(p,'containerType','null',@ischar);
    addParameter(p,'containerTag','null',@ischar);
    addParameter(p,'description',[],@ischar);
    addParameter(p,'datasetDOI',[],@ischar);
    addParameter(p,'datasetURL',[],@ischar);
    addParameter(p,'datasetVersion',[],@ischar);
    addParameter(p,'sesFolder',[],@islogical);
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

    if nargin > 2
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
    
    Model = filter_map; 
    data = struct();
    
    if nargin > 2

        if any(cellfun(@isequal,varargin,repmat({'siemens'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'siemens'},size(varargin)))==1);
            issiemens = varargin{idx+1};
        else
            issiemens = 0;
        end

        if any(cellfun(@isequal,varargin,repmat({'mask'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'mask'},size(varargin)))==1);
            data.Mask = double(load_nii_data(varargin{idx+1}));
        end
    
        if any(cellfun(@isequal,varargin,repmat({'type'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'type'},size(varargin)))==1);
            Model.options.Smoothingfilter_Type = varargin{idx+1};
        end
    
        if any(cellfun(@isequal,varargin,repmat({'dimension'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'dimension'},size(varargin)))==1);
            Model.options.Smoothingfilter_Dimension = varargin{idx+1};
        end
    
        if any(cellfun(@isequal,varargin,repmat({'order'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'order'},size(varargin)))==1);
            Model.options.Smoothingfilter_order = varargin{idx+1};
        end
    
        if any(cellfun(@isequal,varargin,repmat({'size'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'size'},size(varargin)))==1);
            sz = varargin{idx+1};
            Model.options.Smoothingfilter_sizex= sz(1);
            Model.options.Smoothingfilter_sizey= sz(2);
            Model.options.Smoothingfilter_sizez= sz(3);     
        end
        
         if any(cellfun(@isequal,varargin,repmat({'sid'},size(varargin))))
            idx = find(cellfun(@isequal,varargin,repmat({'sid'},size(varargin)))==1);
            SID = varargin{idx+1};
         else
            SID = [];
        end

    end 
    
    data.Raw = double(load_nii_data(b1plus_nii));

    % TODO: 
    % Check if Octave is OK with inputParser (and MATLAB version range)
    % If so use it to reduce the verbosity below.

    if issiemens
        data.Raw = data.Raw./800;
    end

    
    % ==== Fit Data ====
    
    FitResults = FitData(data,Model,0);
    
    outPrefix = FitResultsSave_BIDS(FitResults,b1plus_nii,SID,'sesFolder',sesFolder);
    
    Model.saveObj([outPrefix '_filter_map.qmrlab.mat']);
    
    if moxunit_util_platform_is_octave
        warning('on','all');
    end
    
    setenv('ISBIDS','');
    setenv('ISNEXTFLOW','');

end
     
    
function qmr_init(qmrdir)

run([qmrdir filesep 'startup.m']);

end