% Simple wrapper for fitting MP2RAGE data at the subject level.
%
% Organization of the multi-subject input files:
%
%     BIDS    See more at https://github.com/bids-standard/bep001.
%             Example BIDS qMRI datasets are available at
%             https://osf.io/8x2c9/
%
%     Custom  See more at qMRLab/qMRflow/mp2rage/USAGE.md    
%
%
% Required inputs:
%
%    Image file names (.nii.gz):
%        - UNIT_nii --> subID_*.nii.gz (e.g. sub-01_UNIT1.nii.gz)
%
%    Metadata files for BIDS (.json): 
%        - UNIT_jsn --> subID_*.json
%
%
% mp2rage_UNIT1_wrapper(___,PARAM1, VAL1,___)
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
%    subID_T1map.nii.gz      Longitudianl relaxation
%                             T1 map.
%    subID_T1map.json        Sidecar json for provenance.
%
%    subID_mp2rage_qmrlab.mat  Object containing qMRLab options. 
% 
% IMPORTANT:
%
%    
%    FitResults.mat     Removed after fitting.
%
%    Subject ID         This wrapper assumes that the input data
%                       has a subject ID prefix before the first
%                       occurence of the '_' character.  
%
% Written by: Agah Karakuzu, Juan Jose Velazquez Reyes | 2021
% GitHub:     @agahkarakuzu, @jvelazquez-reyes
%
% Intended use: qMRFlow 
% =========================================================================


function mp2rage_neuromod(SID,UNIT_nii,UNIT_jsn,varargin)

    disp('Runnning mp2rage neuromod latest');

    if moxunit_util_platform_is_octave
       warning('off','all');
    end
    
    validDir = @(x) exist(x,'dir');
    
    keyval = regexp(SID,'[^-_]*','match');
    
    p = inputParser();
    
    %Input parameters conditions
    validNii = @(x) exist(x,'file') && strcmp(x(end-5:end),'nii.gz');
    validJsn = @(x) exist(x,'file') && strcmp(x(end-3:end),'json');
    
    %Add REQUIRED Parameteres
    addRequired(p,'SID',@ischar);
    addRequired(p,'UNIT_nii',validNii);
    addRequired(p,'UNIT_jsn',validJsn);
    
    %Add OPTIONAL Parameteres
    addParameter(p,'mask',[],validNii);
    addParameter(p,'b1map',[],validNii);
    addParameter(p,'qmrlab_path',[],@ischar);
    addParameter(p,'containerType','null',@ischar);
    addParameter(p,'containerTag','null',@ischar);
    addParameter(p,'description',[],@ischar);
    addParameter(p,'datasetDOI',[],@ischar);
    addParameter(p,'datasetURL',[],@ischar);
    addParameter(p,'datasetVersion',[],@ischar);
    addParameter(p,'sesFolder',false,@islogical);
    addParameter(p,'targetDir',[],validDir);
    
    parse(p,SID,UNIT_nii,UNIT_jsn,varargin{:});
    
    SID = p.Results.SID;
    UNIT_nii = p.Results.UNIT_nii;
    UNIT_jsn = p.Results.UNIT_jsn;
    
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
        qMRLabVer();
    end
    
    % ==== Set Protocol ====
    Model = mp2rage;
    data = struct();
    
    % Load data
    data.MP2RAGE=double(load_nii_data(p.Results.UNIT_nii));
    
    %Account for optional inputs and options
    if ~isempty(p.Results.mask); data.Mask = double(load_nii_data(p.Results.mask)); end
    if ~isempty(p.Results.b1map); data.B1map = double(load_nii_data(p.Results.b1map)); end
    
    %Set protocol
    protJson = json2struct(UNIT_jsn);
    
    Model.Prot.Hardware.Mat = protJson.MagneticFieldStrength;
    
    cprintf('magenta','<< Based on anatomical_protocol_2019-01-22.pdf >> NEUROMOD GENERIC: RepetitionTimeExcitation %s','3.5'); 
    Model.Prot.RepetitionTimes.Mat = [protJson.RepetitionTime;0.0035];
    
    cprintf('magenta','<< Based on anatomical_protocol_2019-01-22.pdf >> NEUROMOD GENERIC: InversionTimes %s','0.7 and 1.5'); 
    Model.Prot.Timing.Mat = [0.7;1.5];
    
    cprintf('magenta','<< Based on anatomical_protocol_2019-01-22.pdf >> NEUROMOD GENERIC: FlipAngles %s','7 and 5'); 
    Model.Prot.Sequence.Mat = [7;5];
    
    % Based on https://docs.cneuromod.ca/en/latest/_static/mri/anatomical_protocol_2019-01-22.pdf
    cprintf('magenta','<< Based on anatomical_protocol_2019-01-22.pdf >> NEUROMOD GENERIC: Assuming Slice partial fourier of %s','6/8'); 
    nPartitions = length(protJson.global.slices.ContentTime);
    Pre  = nPartitions*(6/8 - 0.5);
    Post = nPartitions/2;
    Model.Prot.NumberOfShots.Mat = [Pre;Post];
    
    % ==== Fit Data ====
    
    FitResults = FitData(data,Model,0);
    
    % JSON file for dataset_description
    addDescription = struct();
    addDescription.BasedOn = {UNIT_nii};
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
    
    addDescription.ProtocolReference = 'https://docs.cneuromod.ca/en/latest/_static/mri/anatomical_protocol_2019-01-22.pdf';
    addDescription.ProtocolLastUpdated = 'April 2021 by agahkarakuzu@gmail.com';
    addDescription.RepetitionTimeInversion = protJson.RepetitionTime;
    addDescription.RepetitionTimeExcitation = 0.0035;
    addDescription.InversionTime = [0.7,1.5];
    addDescription.FlipAngle = [7,5];
    addDescription.SlicePartialFourier = 0.75;
    addDescription.NumberOfSlices = nPartitions;
    addDescription.NumberOfShots = [Pre Post];
    
    outPrefix = FitResultsSave_BIDS(FitResults,UNIT_nii,SID,'injectToJSON',addDescription,'sesFolder',sesFolder,'acq','MP2RAGE');
    
    Model.saveObj([outPrefix '_mp2rage.qmrlab.mat']);
    
    if moxunit_util_platform_is_octave
        warning('on','all');
    end
    
    setenv('ISBIDS','');
    setenv('ISNEXTFLOW','');

end
    
    function out = json2struct(filename)
    
    tmp = loadjson(filename);
    
    if isstruct(tmp)
    
        out = tmp;
    
    else
    
        str = cell2struct(tmp,'tmp');
        out = [str.tmp];
    
    end
    
    end 
    
    function qmr_init(qmrdir)
    
    run([qmrdir filesep 'startup.m']);
    
    end