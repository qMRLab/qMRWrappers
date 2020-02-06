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

function mt_ratio_wrapper(mton_nii,mtoff_nii,varargin)

%if moxunit_util_platform_is_octave
%    warning('off','all');
%end

% This env var will be consumed by qMRLab
setenv('ISNEXTFLOW','1');

if nargin >2
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

Model = mt_ratio; 
data = struct();

if nargin>2
    
    if any(cellfun(@isequal,varargin,repmat({'mask'},size(varargin))))
        idx = find(cellfun(@isequal,varargin,repmat({'mask'},size(varargin)))==1);
        data.Mask = double(load_nii_data(varargin{idx+1}));
    end
    
    if any(cellfun(@isequal,varargin,repmat({'sid'},size(varargin))))
        idx = find(cellfun(@isequal,varargin,repmat({'sid'},size(varargin)))==1);
        SID = varargin{idx+1};
    else
        SID = [];
    end
    
 
end


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


% ==== Save outputs ==== 
disp('-----------------------------');
disp('Saving fit results...');

FitResultsSave_nii(FitResults,mton_nii,pwd);

% ==== Rename outputs ==== 
if ~isempty(SID)
    movefile('MTR.nii.gz',[SID '_MTRmap.nii.gz']);
else
    movefile('MTR.nii.gz','MTRmap.nii.gz'); 
end

% Save qMRLab object
if ~isempty(SID)
    Model.saveObj([SID '_mt_ratio.qmrlab.mat']);
else
    Model.saveObj('mt_ratio.qmrlab.mat');    
end

% Remove FitResults.mat 
delete('FitResults.mat');

addField = struct();
addField.EstimationReference =  'Semi-quantitative parameter.';
addField.EstimationAlgorithm =  'MTR=(MToff-MTon)/MToff';
addField.BasedOn = [{mton_nii},{mtoff_nii}];

provenance = Model.getProvenance('extra',addField);

if ~isempty(SID)
    savejson('',provenance,[pwd filesep SID '_MTRmap.json']);
else
    savejson('',provenance,[pwd filesep 'MTRmap.json']);
end

if ~isempty(SID)
disp(['Success: ' SID]);
disp('-----------------------------');
disp('Saved: ');
disp(['    ' SID '_MTRmap.nii.gz'])
disp(['    ' SID '_MTRmap.json'])
disp('=============================');
end

if moxunit_util_platform_is_octave
    warning('on','all');
end


end

function qmr_init(qmrdir)

run([qmrdir filesep 'startup.m']);

end