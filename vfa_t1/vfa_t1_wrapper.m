% Simple wrapper for fitting VFAT1 data at the subject level.
%
% Organization of the multi-subject input files:
%
%     BIDS    See more at https://github.com/bids-standard/bep001.
%             Example BIDS qMRI datasets are available at
%             https://osf.io/k4bs5/
%
%     Custom  See more at qMRLab/qMRflow/mt_sat/USAGE.md    
%
%
% Required inputs:
%
%    Image file names (.nii.gz):
%        - mtw_nii --> subID_*.nii.gz (e.g. sub-01_acq-MTon_MTS.nii.gz)
%        - pdw_nii --> subID_*.nii.gz (e.g. sub-01_acq-MToff_MTS.nii.gz)
%        - t1w_nii --> subID_*.nii.gz (e.g. sub-01_acq-T1w_MTS.nii.gz) 
%
%    Metadata files for BIDS (.json): 
%        - mtw_jsn --> subID_*.json
%        - pdw_jsn --> subID_*.json
%        - t1w_jsn --> subID_*.json
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
%    Subject ID         This wrapper assumes that the input data
%                       has a subject ID prefix before the first
%                       occurence of the '_' character.  
%
% Written by: Agah Karakuzu, 2020
% GitHub:     @agahkarakuzu
%
% Intended use: qMRFlow 
% =========================================================================


function vfa_t1_wrapper(nii_array,json_array)

%if moxunit_util_platform_is_octave
%    warning('off','all');
%end

% Deal with these later with agparser. 
%{
% This env var will be consumed by qMRLab
setenv('ISNEXTFLOW','1');

if nargin >6
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
%}

% Quite temporary 
tmpName = nii_array{1};
flipLoc2 = strfind(tmpName,'_flip');
flipLoc1 = max(strfind(tmpName,filesep)) + 1;
SID = tmpName(flipLoc1:flipLoc2-1);

Model = vfa_t1; 
data = struct();

qLen = length(nii_array);

tmp = double(load_nii_data(tmpName));
sz = size(tmp); 
data.VFAData = zeros(sz(1),sz(2),sz(3),qLen);
Model.Prot.VFAData.Mat = zeros(qLen,2);

for ii = 1:qLen
   data.VFAData(:,:,:,ii) =  double(load_nii_data(nii_array{ii}));
   Model.Prot.VFAData.Mat(ii,1) = getfield(json2struct(json_array{ii}),'FlipAngle');
   Model.Prot.VFAData.Mat(ii,2)  =getfield(json2struct(json_array{ii}),'RepetitionTime')/1000;
end

% ==== Fit Data ====

FitResults = FitData(data,Model,0);

% ==== Weed out spurious values ==== 

% Zero-out Inf values (caused by masking)
FitResults.T1(FitResults.T1==Inf)=0;
% Null-out negative values 
FitResults.T1(FitResults.T1<0)=NaN;

% Zero-out Inf values (caused by masking)
FitResults.M0(FitResults.M0==Inf)=0;
% Null-out negative values 
FitResults.M0(FitResults.M0<0)=NaN;

% ==== Save outputs ==== 
disp('-----------------------------');
disp('Saving fit results...');

FitResultsSave_nii(FitResults,nii_array{1},pwd);

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
    Model.saveObj([SID '_mt_sat.qmrlab.mat']);
else
    Model.saveObj('mt_sat.qmrlab.mat');    
end

% Remove FitResults.mat 
delete('FitResults.mat');

addField = struct();
addField.EstimationReference =  'Fram, E.K. et al. (1987), Magn Reson Imaging, 5:201-208';
addField.EstimationAlgorithm =  'src/Models_Functions/MTV/Compute_M0_T1_OnSPGR.m';
addField.BasedOn = nii_array;

provenance = Model.getProvenance('extra',addField);

if ~isempty(SID)
    savejson('',provenance,[pwd filesep SID '_T1map.json']);
    savejson('',provenance,[pwd filesep SID '_M0map.json']);
else
    savejson('',provenance,[pwd filesep 'T1map.json']);
    savejson('',provenance,[pwd filesep 'M0map.json']);
end

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