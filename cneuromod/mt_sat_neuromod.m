% Simple wrapper for fitting MTSAT data at the subject level.
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


function mt_sat_wrapper(SID, mtw_nii,pdw_nii,t1w_nii,mtw_jsn,pdw_jsn,t1w_jsn,varargin)

if moxunit_util_platform_is_octave
    warning('off','all');
end

keyval = regexp(fname,'[^-_]*','match');
table = cell2table(keyval(2:2:end),'VariableNames',keyval(1:2:end-1));

% This env var will be consumed by qMRLab
setenv('ISNEXTFLOW','1');
setenv('ISBIDS','1');

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

Model = mt_sat; 
data = struct();

customFlag = 0;
if all([isempty(mtw_jsn) isempty(pdw_jsn) isempty(t1w_jsn)]); customFlag = 1; end; 

% Account for optional inputs and options.
if nargin>6
    
    
    if any(cellfun(@isequal,varargin,repmat({'mask'},size(varargin))))
        idx = find(cellfun(@isequal,varargin,repmat({'mask'},size(varargin)))==1);
        data.Mask = double(load_nii_data(varargin{idx+1}));
    end
    
    if any(cellfun(@isequal,varargin,repmat({'b1map'},size(varargin))))
        idx = find(cellfun(@isequal,varargin,repmat({'b1map'},size(varargin)))==1);
        data.B1map = double(load_nii_data(varargin{idx+1}));
    end
    
    if any(cellfun(@isequal,varargin,repmat({'b1factor'},size(varargin))))
        idx = find(cellfun(@isequal,varargin,repmat({'b1factor'},size(varargin)))==1);
        Model.options.B1correctionfactor = varargin{idx+1};
    end
    
    
    
    if customFlag
        % Collect parameters when non-BIDS pipeline is used.
        
           
           idx = find(cellfun(@isequal,varargin,repmat({'custom_json'},size(varargin)))==1);
           prt = json2struct(varargin{idx+1});
           
           % Set protocol from mt_sat_prot.json
           Model.Prot.MTw.Mat =[prt.MTw.FlipAngle prt.MTw.RepetitionTime];
           Model.Prot.PDw.Mat =[prt.PDw.FlipAngle prt.PDw.RepetitionTime];
           Model.Prot.T1w.Mat =[prt.T1w.FlipAngle prt.T1w.RepetitionTime];
           
    end
         
    
end


% Load data
data.MTw=double(load_nii_data(mtw_nii));
data.PDw=double(load_nii_data(pdw_nii));
data.T1w=double(load_nii_data(t1w_nii));


if ~customFlag

    Model.Prot.MTw.Mat =[getfield(json2struct(mtw_jsn),'FlipAngle') getfield(json2struct(mtw_jsn),'RepetitionTime')];
    Model.Prot.PDw.Mat =[getfield(json2struct(pdw_jsn),'FlipAngle') getfield(json2struct(pdw_jsn),'RepetitionTime')];
    Model.Prot.T1w.Mat =[getfield(json2struct(t1w_jsn),'FlipAngle') getfield(json2struct(t1w_jsn),'RepetitionTime')];

end

% ==== Fit Data ====

FitResults = FitData(data,Model,0);

% ==== Weed out spurious values ==== 

% Zero-out Inf values (caused by masking)
FitResults.T1(FitResults.T1==Inf)=0;
% Null-out negative values 
FitResults.T1(FitResults.T1<0)=NaN;

% Zero-out Inf values (caused by masking)
FitResults.MTSAT(FitResults.MTSAT==Inf)=0;
% Null-out negative values 
FitResults.MTSAT(FitResults.MTSAT<0)=NaN;

addDescription = struct();
addDescription.BasedOn = [{nii_array},{json_array}];
addDescription.GeneratedBy.Container.Type = p.Results.containerType;
if ~strcmp(p.Results.containerTag,'null'); addDescription.GeneratedBy.Container.Tag = p.Results.containerTag; end
addDescription.GeneratedBy.Name2 = 'Manual';
addDescription.GeneratedBy.Description = p.Results.description;
if ~isempty(p.Results.datasetDOI); addDescription.SourceDatasets.DOI = p.Results.datasetDOI; end
if ~isempty(p.Results.datasetURL); addDescription.SourceDatasets.URL = p.Results.datasetURL; end
if ~isempty(p.Results.datasetVersion); addDescription.SourceDatasets.Version = p.Results.datasetVersion; end

FitResultsSave_nii(FitResults,nii_array{1},pwd);

FitResultsSave_BIDS(FitResults,nii_array{1},SID,'injectToJSON',addDescription);


Model.saveObj([SID '_mt_ratio.qmrlab.mat']);



% Remove FitResults.mat 
delete('FitResults.mat');

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