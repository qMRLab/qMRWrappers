% Simple wrapper for fitting MTR data at the subject level.
%
%
% Required inputs:
%
%    Image file names (.nii.gz):
%        - mton_nii --> subID_*.nii.gz (e.g. sub-01_acq-MTon_MTR.nii.gz)
%        - mtoff_nii --> subID_*.nii.gz (e.g. sub-01_acq-MToff_MTR.nii.gz)
%
% mt_sat_wrapper(___,PARAM1, VAL1, PARAM2, VAL2,___)
%
% Parameters include:
%
%   'mask'              File name for the (.nii.gz formatted)
%                       binary mask. (string)
%
%   'qmrlab_path'       Absolute path to the qMRLab's root directory. (string)
%
% Outputs: 
%
%    subID_MTRmap.nii.gz       Magnetization transfer saturation
%                             index map.
%    subID_MTRmap.json         Sidecar json for provenance.
%
%    subID_mt_ratio_qmrlab.mat  Object containing qMRLab options. 
% 
% NOTE:
%
%    FitResults.mat     Removed after fitting.
%
%
% Written by: Agah Karakuzu, 2020
% GitHub:     @agahkarakuzu
%
% Intended use: qMRFlow 
% =========================================================================

function mt_ratio_neuromod(SID,mton_nii,mtoff_nii,varargin)

    disp('Runnning mtratio neuromod latest');

    if moxunit_util_platform_is_octave
        warning('off','all');
    end

    validDir = @(x) exist(x,'dir');
    
    keyval = regexp(SID,'[^-_]*','match');
    
    p = inputParser();
    
    %Input parameters conditions
    validNii = @(x) exist(x,'file') && strcmp(x(end-5:end),'nii.gz');
    
    addParameter(p,'mask',[],validNii);
    addParameter(p,'qmrlab_path',[],@ischar);
    addParameter(p,'containerType','null',@ischar);
    addParameter(p,'containerTag','null',@ischar);
    addParameter(p,'description',[],@ischar);
    addParameter(p,'datasetDOI',[],@ischar);
    addParameter(p,'datasetURL',[],@ischar);
    addParameter(p,'datasetVersion',[],@ischar);
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
    
    Model = mt_ratio;
    data = struct();
    
    if ~isempty(p.Results.mask); data.Mask = double(load_nii_data(p.Results.mask)); end
    
    % Load data
    data.MTon=double(load_nii_data(mton_nii));
    data.MToff=double(load_nii_data(mtoff_nii));
    
    % ==== Fit Data ====
    
    FitResults = FitData(data,Model,0);
    
    % ==== Weed out spurious values ====
    
    % Zero-out Inf values (caused by masking)
    FitResults.MTR(FitResults.MTR==Inf)=0;
    % Null-out negative values
    FitResults.MTR(FitResults.MTR<0)=NaN;
    
    addDescription = struct();
    addDescription.BasedOn = [{mton_nii},{mtoff_nii}];
    addDescription.GeneratedBy.Container.Type = p.Results.containerType;
    if ~strcmp(p.Results.containerTag,'null'); addDescription.GeneratedBy.Container.Tag = p.Results.containerTag; end
    if isempty(p.Results.description)
        addDescription.GeneratedBy.Description = 'qMRFlow';
    else
        addDescription.GeneratedBy.Description = p.Results.description;
    end
    if ~isempty(p.Results.datasetDOI); addDescription.SourceDatasets.DOI = p.Results.datasetDOI; end
    if ~isempty(p.Results.datasetURL); addDescription.SourceDatasets.URL = p.Results.datasetURL; end
    if ~isempty(p.Results.datasetVersion); addDescription.SourceDatasets.Version = p.Results.datasetVersion; end
    
    outPrefix = FitResultsSave_BIDS(FitResults,mton_nii,SID,'injectToJSON',addDescription,'sesFolder',sesFolder);
    
    Model.saveObj([SID '_mt_ratio.qmrlab.mat']);
    
    if moxunit_util_platform_is_octave
        warning('on','all');
    end
    
    setenv('ISBIDS','');
    setenv('ISNEXTFLOW','');

end

function qmr_init(qmrdir)

run([qmrdir filesep 'startup.m']);

end