function regionStats(maskList,mapList,csvName)

masks = struct();
for ii = 1:length(maskList)
    
    %masks(ii).Mask = double( load_nii_data(maskList{ii}));
    masks(ii).Filename = maskList{ii}; 
    masks(ii).Entity = parseEntity(maskList{ii});
    
    if isempty(masks(ii).Entity.label)
       warning(['Mask region is not identified: ' maskList{ii}]);
    end
end

maps = struct();
for ii = 1:length(mapList)
    %maps(ii).Map = double(load_nii_data(mapList{ii}));
    maps(ii).Filename = mapList{ii}; 
    maps(ii).Entity = parseEntity(mapList{ii});
end

csvData = {};

it = 1;
for ii=1:length(maps)
    for jj=1:length(masks)
   
        if isequal(maps(ii).Entity.sub,masks(jj).Entity.sub) && isequal(maps(ii).Entity.ses,masks(jj).Entity.ses)
            
            curMap = double(load_nii_data(maps(ii).Filename));
            curMask = double(load_nii_data(masks(jj).Filename));
            
            % Because of slab profile effects, mask-out the top and bottom 20 slices from the qMR maps derived from the MTsat measurements.
            if ~isempty(maps(ii).Entity.acq)
                if contains(maps(ii).Filename, '-MTS_') || contains(maps(ii).Filename, '_MTRmap')
                    curMap(:,:,1:20) = 0;
                    curMap(:,:,end-20:end) = 0;
                end
            end

            curVec = curMap(curMask==1);

            curMeta = json2struct(maps(ii).Entity.json);
            csvData(it,1) = maps(ii).Entity.sub; 
            csvData(it,2) = maps(ii).Entity.ses;
            try
                csvData(it,3) = upper(maps(ii).Entity.acq);
            catch
                csvData(it,3) = {'N/A'};
            end
            csvData(it,4) = maps(ii).Entity.suffix;
            
            switch maps(ii).Entity.suffix{:}
               
                case 'T1map'
                    csvData(it,5) = {'second'};
                case 'MTRmap'
                    csvData(it,5) = {'percent'};
                case 'MTsat'
                    csvData(it,5) = {'arbitrary'};    
            end
            
            csvData(it,6) = masks(jj).Entity.label;
            csvData(it,7) = num2cell(nanmean(curVec));
            csvData(it,8) = num2cell(nanstd(curVec));
            csvData(it,9) = num2cell(nanmedian(curVec));
            csvData(it,10) = num2cell(iqr(curVec));
            csvData(it,11) = num2cell(min(curVec));
            csvData(it,12) = num2cell(max(curVec));
            csvData(it,13) = num2cell(prctile(curVec,25));
            csvData(it,14) = num2cell(prctile(curVec,75));
            csvData(it,15) = {maps(ii).Filename};
            csvData(it,16) = {masks(jj).Filename};
            csvData(it,17) = {[curMeta.EstimationSoftwareName ' ' num2str(curMeta.EstimationSoftwareVer)]};
            csvData(it,18) = {curMeta.EstimationDate};
            csvData(it,19) = {strjoin(cellstr([curMeta.BasedOn{:}]),'|')};
            csvData(it,20) = {curMeta.EstimationSoftwareLang};
            csvData(it,21) = {curMeta.EstimationSoftwareEnv};
            try
                csvData(it,22) = {curMeta.EstimationReference};
            catch
                csvData(it,22) = {'N/A'};
            end
            csvData(it,23) = {curMeta.DatasetType};

            it = it+1;
        end
    end
end

cHeader = {'subject','session','acquisition','metric','unit', 'label','mean','std','median','iqr','min','max','q1','q3','map','mask','software','date','map_basedon','runtime','OS','map_reference','data_type'}; 

%csvName = ['sub-' maps(1).Entity.sub{:} '_ses-' maps(1).Entity.ses{:} '_' masks(1).Entity.suffix{:} '_stats.csv'];

csvData = [cHeader;csvData];
cell2csv(csvName,csvData,',');

% 'sub-01_ses-001_acq-mp2rage_T1map.nii.gz'
% ['sub-01_ses-001_label-GM_MP2RAGE.nii.gz','sub-01_ses-001_label-WM_MP2RAGE.nii.gz'];

%['sub-01_ses-001_label-GM_MTS.nii.gz', 'sub-01_ses-001_label-WM_MTS.nii.gz'];
%'sub-01_ses-001_acq-MTS_T1map.nii.gz','sub-01_ses-001_acq-MTS_MTsat.nii.gz','sub-01_ses-001_MTRmap.nii.gz'];


end

function out = parseEntity(fname)

out = struct();
out.json = [fname(1:end-7) '.json'];

locs = strfind(fname,filesep);

if ~isempty(locs)
    fname = fname(max(locs)+1:end);
end


out.sub = regexp(fname,'(?<=sub-).*?(?=_)','match');
out.ses = regexp(fname,'(?<=ses-).*?(?=_)','match');
out.acq = regexp(fname,'(?<=acq-).*?(?=_)','match');
out.label = regexp(fname,'(?<=label-).*?(?=_)','match');
out.suffix = regexp(fname,'(?!.*_).*?(?=.nii.gz)','match');


end

function cell2csv(filename,cellArray,delimiter)
% Writes cell array content into a *.csv file.
% 
% CELL2CSV(filename,cellArray,delimiter)
%
% filename      = Name of the file to save. [ i.e. 'text.csv' ]
% cellarray    = Name of the Cell Array where the data is in
% delimiter = seperating sign, normally:',' (default)
%
% by Sylvain Fiedler, KA, 2004
% modified by Rob Kohr, Rutgers, 2005 - changed to english and fixed delimiter
if nargin<3
    delimiter = ',';
end

datei = fopen(filename,'w');
for z=1:size(cellArray,1)
    for s=1:size(cellArray,2)

        var = eval(['cellArray{z,s}']);

        if size(var,1) == 0
            var = '';
        end

        if isnumeric(var) == 1
            var = num2str(var);
        end

        fprintf(datei,var);

        if s ~= size(cellArray,2)
            fprintf(datei,[delimiter]);
        end
    end
    fprintf(datei,'\n');
end
fclose(datei);
end
