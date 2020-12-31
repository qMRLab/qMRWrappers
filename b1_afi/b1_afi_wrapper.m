% Simple wrapper for fitting AFI data at the subject level.
%
% Organization of the multi-subject input files:
%
%     BIDS    See more at https://github.com/bids-standard/bep001.
%             Example BIDS qMRI datasets are available at
%             https://osf.io/csjgx/
%
%     Custom  See more at qMRLab/qMRflow/b1_afi/USAGE.md    
%
%
% Required inputs:
%
%    Image file names (.nii.gz):
%        - AFIData1_nii --> subID_*.nii.gz (e.g. sub-01_acq-tr1_TB1AFI.nii.gz)
%        - AFIData2_nii --> subID_*.nii.gz (e.g. sub-01_acq-tr2_TB1AFI.nii.gz) 
%
%    Metadata files for BIDS (.json): 
%        - AFIData1_jsn --> subID_*.json
%        - AFIData2_jsn --> subID_*.json
%
%    Metadata files for customized convention: 
%      
%        - b1_afi_prot.json
%
% b1_afi_wrapper(___,PARAM1, VAL1, PARAM2, VAL2,___)
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
%    subID_TB1map.nii.gz      Actual Flip-Angle Imaging
%                             B1+ map.
%    subID_TB1map.json        Sidecar json for provenance.
%
%    subID_b1_afi_qmrlab.mat  Object containing qMRLab options. 
% 
% IMPORTANT:
%
%    Spurious values    Set to 0.6 (masking).
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


function b1_afi_wrapper(AFIData1_nii,AFIData2_nii,AFIData1_jsn,AFIData2_jsn,varargin)

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
addRequired(p,'AFIData1_nii',validNii);
addRequired(p,'AFIData2_nii',validNii);
addRequired(p,'AFIData1_jsn',validJsn);
addRequired(p,'AFIData2_jsn',validJsn);

%Add OPTIONAL Parameteres
addParameter(p,'mask',[],validNii);
addParameter(p,'qmrlab_path',[],@ischar);
addParameter(p,'sid',[],@ischar);
addParameter(p,'containerType',@ischar);
addParameter(p,'containerTag',[],@ischar);
addParameter(p,'description',@ischar);
addParameter(p,'datasetDOI',[],@ischar);
addParameter(p,'datasetURL',[],@ischar);
addParameter(p,'datasetVersion',[],@ischar);

parse(p,AFIData1_nii,AFIData2_nii,AFIData1_jsn,AFIData2_jsn,varargin{:});

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
Model = b1_afi;
data = struct();

% Load data
data.AFIData1=double(load_nii_data(AFIData1_nii));
data.AFIData2=double(load_nii_data(AFIData2_nii));

%Account for optional inputs and options
if ~isempty(p.Results.mask); data.Mask = double(load_nii_data(p.Results.mask)); end
if ~isempty(p.Results.sid); SID = p.Results.sid; end

customFlag = 0;
if all([isempty(AFIData1_jsn) isempty(AFIData2_jsn)]); customFlag = 1; end

if customFlag
    % Collect parameters when non-BIDS pipeline is used.
    idx = find(cellfun(@isequal,varargin,repmat({'custom_json'},size(varargin)))==1);
    prt = json2struct(varargin{idx+1});
    
    % Set protocol from b1_afi_prot.json
    Model.Prot.Sequence.Mat=[prt.Sequence.nomFA; prt.Sequence.RepetitionTime1; prt.Sequence.RepetitionTime2];
end

if ~customFlag

    % RepetitionTime in BIDS (s)
    % qMRLab Repetition time is in (s). 
    Model.Prot.Sequence.Mat =[getfield(json2struct(AFIData1_jsn),'nomFA') getfield(json2struct(AFIData1_jsn),'RepetitionTime1') getfield(json2struct(AFIData2_jsn),'RepetitionTime2')];

end

% ==== Fit Data ====

FitResults = FitData(data,Model,0);

% ==== Weed out spurious values ==== 


% ==== Save outputs ==== 
disp('-----------------------------');
disp('Saving fit results...');

FitResultsSave_nii(FitResults,AFIData1_nii,pwd);

% ==== Rename outputs ==== 
if ~isempty(SID)
    movefile('B1map_raw.nii.gz',[SID '_TB1map.nii.gz']);
else
    movefile('B1map_raw.nii.gz','TB1map.nii.gz');  
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