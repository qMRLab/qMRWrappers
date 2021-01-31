% Fit (ideally BIDS compatible) VFAT1 data for a single subject.
% This script is mainly intended (but not limited) for use with qMRFlow.
%
% Dependencies:
%       
%     qMRLab (>= v2.3.1)
%     Octave (>= v4.2.0) or MATLAB (>R2014b)
%
% Documentation:
%
%     qMRFlow https://qmrlab.readthedocs.io/en/master/qmrflow_intro.html
%     BIDS    http://bids-specification.readthedocs.io/ 
%
% Organization of the multi-subject input files:
%
%     BIDS    See more at https://github.com/bids-standard/bep001.
%             Example BIDS qMRI datasets are available at
%             https://osf.io/7wcvh/
%
%     Custom  See more at qMRLab/qMRflow/vfa_t1/USAGE.md    
%
% Required inputs:
%
%    Image file names (.nii.gz):
%        - mtw_nii --> subID_flip-01_mt-on_MTS.nii.gz   (e.g. sub-01_acq-sie_flip-01_mt-on_MTS.nii.gz)
%        - pdw_nii --> subID_flip-01_mt-off_MTS.nii.gz  (e.g. sub-01_acq-sie_flip-01_mt-off_MTS.nii.gz)
%        - t1w_nii --> subID_flip-02_mt-off_MTS.nii.gz  (e.g. sub-01_acq-sie_flip-02_mt-off_MTS.nii.gz)
%                                           
%    Metadata files for BIDS (.json): 
%        - mtw_jsn --> subID_flip-01_mt-on_MTS.json
%        - pdw_jsn --> subID_flip-01_mt-off_MTS.json
%        - t1w_jsn --> subID_flip-02_mt-off_MTS.json
%
%    Metadata files for customized convention: 
%      
%        - mt_sat_prot.json
%
% mt_sat_wrapper(___,PARAM1, VAL1, PARAM2, VAL2,___)
%
% Parameters include:
%
%   'mask'              File name for the (.nii.gz formatted)
%                       binary mask. (string)
%
%   'b1map'             File name for the (.nii.gz formatted)
%                       transmit field (B1 plus) map. (string)
%
%   'b1factor'          B1 correction factor [0-1]. Default: 0.4 (double)
%
%   'qmrlab_path'       Absolute path to the qMRLab's root directory. (string)
%
%   'sid'               Subject ID
%
% Parameters also include BIDS dataset_description.json fields:
% 
%   Documentation       https://bids-specification.readthedocs.io/en/stable/03-modality-agnostic-files.html#derived-dataset-and-pipeline-description
%   
%   Available params    'description'    (string)
%                       'containerTag'   (string)
%                       'containerType'  (string)
%                       'datasetDOI'     (string)
%                       'datasetURL'     (string)
%                       'datasetVersion' (string)
% Outputs: 
%
%    subID_MTsat.nii.gz       Magnetization transfer saturation
%                             index map.
%    subID_MTsat.json         Sidecar json for provenance.
%
%    subID_T1map.nii.gz       Longitudinal relaxation time map
%                             in seconds (s).
%    subID_T1map.json         Sidecar json for provenance.
%
%    subID_mt_sat_qmrlab.mat  Object containing qMRLab options. 
% 
% IMPORTANT:
%
%    Spurious values    Inf values are set to 0 (masking), negative
%                       values are set to NaN (imperfect fit).
%    
%    FitResults.mat     Removed after fitting.
%
%    Subject ID         If not passed, output names will be T1map 
%                       and MTsat. Otherwise, will be appended by
%                       any custom string provided.
%                       In qMRFlow, any BIDS entity prevailing the 
%                       MTS entities (flip, mt) will be recognized 
%                       as a subject ID to be iterated over. 
%
% Written by: Agah Karakuzu, Juan Jose Velazquez Reyes | 2020
% GitHub:     @agahkarakuzu, @jvelazquez-reyes
%
% Intended use: qMRFlow (https://github.com/qmrlab/qmrflow)
% =========================================================================

function vfa_t1_wrapper2(requiredArgs_nii,requiredArgs_jsn,varargin)

% Supress verbose Octave warnings.
%if moxunit_util_platform_is_octave
%    warning('off','all');
%end

% This env var will be consumed by qMRLab
setenv('ISNEXTFLOW','1');

p = inputParser();

%Input parameters conditions
validNii = @(x) exist(x,'file') && strcmp(x(end-5:end),'nii.gz');
validJsn = @(x) exist(x,'file') && strcmp(x(end-3:end),'json');
validB1factor = @(x) isnumeric(x) && (x > 0 && x <= 1);

%Add OPTIONAL Parameteres
addParameter(p,'mask',[],validNii);
addParameter(p,'b1map',[],validNii);
addParameter(p,'b1factor',[],validB1factor);
addParameter(p,'qmrlab_path',[],@ischar);
addParameter(p,'sid',[],@ischar);
addParameter(p,'containerType',@ischar);
addParameter(p,'containerTag',[],@ischar);
addParameter(p,'description',@ischar);
addParameter(p,'datasetDOI',[],@ischar);
addParameter(p,'datasetURL',[],@ischar);
addParameter(p,'datasetVersion',[],@ischar);

parse(p,varargin{:});

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
Model = vfa_t1;
data = struct();

sample = double(load_nii_data(requiredArgs_nii{1}));
qLen = length(requiredArgs_nii);
sz = size(sample);

% Load data
if ndims(sample)==2
    data.VFAData = zeros(sz(1),sz(2),1,qLen);
elseif ndims(sample)==3
    data.VFAData = zeros(sz(1),sz(2),sz(3),qLen);
end

Model.Prot.VFAData.Mat = zeros(qLen,2);

for ii=1:qLen
    if ndims(sample)==2
        data.VFAData(:,:,ii) = double(load_nii_data(requiredArgs_nii{ii}));
        Model.Prot.VFAData.Mat(ii,1) = getfield(json2struct(requiredArgs_jsn{ii}),'FlipAngle');
        Model.Prot.VFAData.Mat(ii,2) = getfield(json2struct(requiredArgs_jsn{ii}),'RepetitionTimeExcitation');
    else
        data.VFAData(:,:,:,ii) = double(load_nii_data(requiredArgs_nii{ii}));
        Model.Prot.VFAData.Mat(ii,1) = getfield(json2struct(requiredArgs_jsn{ii}),'FlipAngle');
        Model.Prot.VFAData.Mat(ii,2) = getfield(json2struct(requiredArgs_jsn{ii}),'RepetitionTimeExcitation');
    end
end

%Account for optional inputs and options
if ~isempty(p.Results.mask); data.Mask = double(load_nii_data(p.Results.mask)); end
if ~isempty(p.Results.b1map); data.b1map = double(load_nii_data(p.Results.b1map)); end
if ~isempty(p.Results.b1factor); Model.options.B1correction = p.Results.b1factor; end
if ~isempty(p.Results.sid); SID = p.Results.sid; end

% ==== Fit Data ====

FitResults = FitData(data,Model,0);

% ==== Weed out spurious values ==== 

% Zero-out Inf values (caused by masking)
FitResults.T1(FitResults.T1==Inf)=0;
% Null-out negative values 
FitResults.T1(FitResults.T1<0)=NaN;

% Zero-out Inf values (caused by masking)
FitResults.MTSAT(FitResults.M0==Inf)=0;
% Null-out negative values 
FitResults.MTSAT(FitResults.M0<0)=NaN;

% ==== Save outputs ==== 
disp('-----------------------------');
disp('Saving fit results...');

FitResultsSave_nii(FitResults,requiredArgs_nii{1},pwd);

% ==== Rename outputs ==== 
if ~isempty(SID)
    movefile('T1.nii.gz',[SID '_T1map.nii.gz']);
    movefile('M0.nii.gz',[SID '_M0map.nii.gz']);
else
    movefile('T1.nii.gz','T1map.nii.gz');
    movefile('M0.nii.gz','M0map.nii.gz');    
end

% Save qMRLab object
if ~isempty(SID)
    Model.saveObj([SID '_vfa_t1.qmrlab.mat']);
else
    Model.saveObj('vfa_t1.qmrlab.mat');    
end

% Remove FitResults.mat 
delete('FitResults.mat');

% JSON files for T1map and MTsat
addField = struct();
addField.EstimationReference =  'Fram, E.K. et al. (1987), Magn Reson Imaging, 5:201-208';
addField.EstimationAlgorithm =  'src/Models_Functions/MTV/Compute_MO_T1_OnSPGR.m';
addField.BasedOn = [{requiredArgs_nii},{requiredArgs_jsn}];

provenance = Model.getProvenance('extra',addField);

if ~isempty(SID)
    savejson('',provenance,[pwd filesep SID '_T1map.json']);
    savejson('',provenance,[pwd filesep SID '_M0map.json']);
else
    savejson('',provenance,[pwd filesep 'T1map.json']);
    savejson('',provenance,[pwd filesep 'M0map.json']);
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
disp(['    ' SID '_M0map.nii.gz'])
disp(['    ' SID '_T1map.json'])
disp(['    ' SID '_M0map.json'])
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
