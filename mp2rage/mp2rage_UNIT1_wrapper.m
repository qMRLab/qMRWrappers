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


function mp2rage_UNIT1_wrapper(UNIT_nii,UNIT_jsn,varargin)

%if moxunit_util_platform_is_octave
%    warning('off','all');
%end

% This env var will be consumed by qMRLab
setenv('ISNEXTFLOW','1');

p = inputParser();

%Input parameters conditions
validNii = @(x) exist(x,'file') && strcmp(x(end-5:end),'nii.gz');
validJsn = @(x) exist(x,'file') && strcmp(x(end-3:end),'json');

%Add REQUIRED Parameteres
addRequired(p,'UNIT_nii',validNii);
addRequired(p,'UNIT_jsn',validJsn);

%Add OPTIONAL Parameteres
addParameter(p,'mask',[],validNii);
addParameter(p,'b1map',[],validNii);
addParameter(p,'qmrlab_path',[],@ischar);
addParameter(p,'sid',[],@ischar);
addParameter(p,'containerType',@ischar);
addParameter(p,'containerTag',[],@ischar);
addParameter(p,'description',@ischar);
addParameter(p,'datasetDOI',[],@ischar);
addParameter(p,'datasetURL',[],@ischar);
addParameter(p,'datasetVersion',[],@ischar);

parse(p,UNIT_nii,UNIT_jsn,varargin{:});

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
if ~isempty(p.Results.sid); SID = p.Results.sid; end

%Set protocol
Model.Prot.Hardware.Mat = getfield(json2struct(UNIT_jsn),'MagneticFieldStrength');
Model.Prot.RepetitionTimes.Mat = [getfield(json2struct(UNIT_jsn),'RepetitionTimeInversion') getfield(json2struct(UNIT_jsn),'RepetitionTimeExcitation')];
Model.Prot.Timing.Mat = getfield(json2struct(UNIT_jsn),'InversionTime');
Model.Prot.Sequence.Mat = getfield(json2struct(UNIT_jsn),'FlipAngle')';
Model.Prot.NumberOfShots.Mat = getfield(json2struct(UNIT_jsn),'NumberShots');

% ==== Fit Data ====

FitResults = FitData(data,Model,0);

% ==== Save outputs ==== 
disp('-----------------------------');
disp('Saving fit results...');

FitResultsSave_nii(FitResults,UNIT_nii,pwd);

% ==== Rename outputs ==== 

if ~isempty(SID)
    movefile('T1.nii.gz',[SID '_T1map.nii.gz']);
else
    movefile('T1.nii.gz','T1map.nii.gz');
end

% Save qMRLab object
if ~isempty(SID)
    Model.saveObj([SID '_mp2rage.qmrlab.mat']);
else
    Model.saveObj('mp2rage.qmrlab.mat');    
end

% Remove FitResults.mat 
delete('FitResults.mat');

% JSON files for TB1map
addField = struct();
addField.EstimationReference =  'Marques, José P., (2010). Neuroimage, 49(2):1271-1281';
addField.EstimationAlgorithm =  'src/Models/T1_relaxometry/mp2rage.m';
addField.BasedOn = {UNIT_nii};

provenance = Model.getProvenance('extra',addField);

if ~isempty(SID)
    savejson('',provenance,[pwd filesep SID '_T1map.json']);
else
    savejson('',provenance,[pwd filesep 'T1map.json']);
end

% JSON file for dataset_description
addDescription = struct();
addDescription.Name = 'qMRLab Outputs';
addDescription.BIDSVersion = '1.5.0';
addDescription.DatasetType = 'derivative';
addDescription.GeneratedBy.Name = 'qMRLab';
addDescription.GeneratedBy.Version = qMRLabVer();
addDescription.GeneratedBy.Container.Type = p.Results.containerType;
if ~strcmp(p.Results.containerTag,'null'); addDescription.GeneratedBy.Container.Tag = p.Results.containerTag; end
addDescription.GeneratedBy.Name2 = 'Manual';
addDescription.GeneratedBy.Description = p.Results.description;
if ~isempty(p.Results.datasetDOI); addDescription.SourceDatasets.DOI = p.Results.datasetDOI; end
if ~isempty(p.Results.datasetURL); addDescription.SourceDatasets.URL = p.Results.datasetURL; end
if ~isempty(p.Results.datasetVersion); addDescription.SourceDatasets.Version = p.Results.datasetVersion; end

savejson('',addDescription,[pwd filesep 'dataset_description.json']);


if ~isempty(SID)
disp(['Success: ' SID]);
disp('-----------------------------');
disp('Saved: ');
disp(['    ' SID '_T1map.nii.gz'])
disp(['    ' SID '_T1map.json'])
disp('=============================');
end

if moxunit_util_platform_is_octave
    warning('on','all');
end


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