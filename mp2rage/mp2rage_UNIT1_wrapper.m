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
data.MP2RAGE=double(load_nii_data(UNIT_nii));

%Account for optional inputs and options
if ~isempty(p.Results.b1map); data.B1map = double(load_nii_data(p.Results.b1map)); end
if ~isempty(p.Results.sid); SID = p.Results.sid; end

%Set protocol
Model.Prot.Hardware.Mat = getfield(json2struct(UNIT_jsn),'MagneticFieldStrength');
Model.Prot.RepetitionTimes.Mat = [getfield(json2struct(UNIT_jsn),'RepetitionTimeInversion') getfield(json2struct(UNIT_jsn),'RepetitionTimeExcitation')];
Model.Prot.Timing.Mat = getfield(json2struct(UNIT_jsn),'InversionTime')';
Model.Prot.Sequence.Mat = getfield(json2struct(UNIT_jsn),'FlipAngle')';
Model.Prot.NumberOfShots.Mat = getfield(json2struct(UNIT_jsn),'NumberShots')';

% Convert naming to the MP2RAGE source code conventions
MP2RAGE.B0 = MagneticFieldStrength;           % in Tesla
MP2RAGE.TR = RepetitionTimeInversion;           % MP2RAGE TR in seconds
MP2RAGE.TRFLASH = RepetitionTimeExcitation; % TR of the GRE readout
MP2RAGE.TIs = InversionTime; % inversion times - time between middle of refocusing pulse and excitatoin of the k-space center encoding
MP2RAGE.NZslices = NumberShots; % Excitations [before, after] the k-space center
MP2RAGE.FlipDegrees = FlipAngle; % Flip angle of the two readouts in degrees

% If both NumberShots are equal, then assume half/half for before/after
if NumberShots(1) == NumberShots(2)
    MP2RAGE.NZslices = [ceil(NumberShots(1)/2) floor(NumberShots(1)/2)]; 
end

if ~isempty(p.Results.b1map)
    [T1corrected, MP2RAGEcorr] = T1B1correctpackageTFL(data.B1map,MP2RAGEimg,[],MP2RAGE,[],invEFF);
            
    FitResult.T1 = T1corrected.img;
    FitResult.R1=1./FitResult.T1;
    FitResult.R1(isnan(FitResult.R1))=0;
    FitResult.MP2RAGEcor = MP2RAGEcorr.img;    
else
    [T1map, R1map]=T1estimateMP2RAGE(MP2RAGEimg,MP2RAGE,invEFF);
        
    FitResult.T1 = T1map.img;
    FitResult.R1 = R1map.img;
end

% ==== Fit Data ====

FitResults = FitData(data,Model,0);

% ==== Save outputs ==== 
disp('-----------------------------');
disp('Saving fit results...');

FitResultsSave_nii(FitResults,AFIData1_nii,pwd);

% ==== Rename outputs ==== 
if strcmp(filtermap,'true')
    if ~isempty(SID)
        movefile('B1map_filtered.nii.gz',[SID '_TB1map.nii.gz']);
    else
        movefile('B1map_filtered.nii.gz','TB1map.nii.gz');
    end
else
    if ~isempty(SID)
        movefile('B1map_raw.nii.gz',[SID '_TB1map.nii.gz']);
    else
        movefile('B1map_raw.nii.gz','TB1map.nii.gz');
    end
end

% Save qMRLab object
if ~isempty(SID)
    Model.saveObj([SID '_b1_afi.qmrlab.mat']);
else
    Model.saveObj('b1_afi.qmrlab.mat');    
end

% Remove FitResults.mat 
delete('FitResults.mat');

% JSON files for TB1map
addField = struct();
addField.EstimationReference =  'Yarnykh, VL., (2007). Magn Reson Med, 57:192-200';
addField.EstimationAlgorithm =  'src/Models/FieldMaps/b1_afi.m';
addField.BasedOn = [{AFIData1_nii},{AFIData2_nii}];

provenance = Model.getProvenance('extra',addField);

if ~isempty(SID)
    savejson('',provenance,[pwd filesep SID '_TB1map.json']);
else
    savejson('',provenance,[pwd filesep 'TB1map.json']);
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
disp(['    ' SID '_TB1map.nii.gz'])
disp(['    ' SID '_TB1map.json'])
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