function table = dat2BIDS(datDir)


datList = dir(fullfile(datDir,'*.dat'));
if ~exist([datDir filesep 'converted'], 'dir'); mkdir([datDir filesep 'converted']); end

table = [];
for ii = 1:length(datList)
    table = [table;getTable(datList(ii).name)];
end

subs = unique(table.sub);

if sum(ismember(table.Properties.VariableNames,'ses'))

sess = cellfun(@(x) unique(table.ses(cellfun(@(y) all(x==y), table.sub))),subs,'UniformOutput',0);

for ii=1:length(sess)

for jj=1:length(sess{ii})
  tmp = sess{ii};
  curFolder = cell2mat(['sub-' subs(ii) filesep 'ses-' tmp{jj} filesep 'anat']);
  if ~exist(curFolder, 'dir')
  mkdir(curFolder);
  end
end
end
else
 cellfun(@(x) mkdir(['sub-' x filesep 'anat']),subs);
end

for ii = 1:length(datList)
    [data, header] = loadDat(datList(ii).name);
    % For now magn
    data = data(1,:) + 1i*data(2,:);
    % Assume vol for now
    data = reshape(data,[header.extent0,header.extent1,header.extent2]);
    movefile([datDir filesep datList(ii).name],[datDir filesep 'converted' filesep datList(ii).name]);
    % Assume float
    % You can save qform later.
    nii = make_nii(data, [header.SpacingX header.SpacingY header.SpacingZ], [header.TranslationX header.TranslationY header.TranslationZ], 64);
    if sum(ismember(table.Properties.VariableNames,'ses'))
        svdir = cell2mat([datDir filesep 'sub-' table(ii,:).sub filesep 'ses-' table(ii,:).ses filesep 'anat']);
    else
        svdir = cell2mat([datDir filesep 'sub-' table(ii,:).sub filesep 'anat']);
    end
    
    save_nii(nii,[svdir filesep datList(ii).name(1:end-4) '.nii.gz']);
    savejson('',header,[svdir filesep datList(ii).name(1:end-4) '.json']);
    
end



end

function [data, header, kspace] = loadDat(fileName)

% Open file
fip = fopen(fileName, 'r', 'l');
if (fip == -1)
  tt = sprintf('File %s not found\n', fileName);
  error(tt);
  return;
end;

% Check that this is an RTHawk file
[magic, count] = fread(fip, 4, 'char');
if (count ~= 4)
  tt = sprintf('Cannot read file format\n');
  error(tt);
  return;
end;

if (sum(magic' ~= ['H' 'O' 'C' 'T']))
	tt = sprintf('Invalid file format\n');
  error(tt);
	return;
end;

% Read version, It should be 1, 2, or 3
[version, count] = fread(fip, 1, 'int');
if (count ~= 1)
  tt = sprintf('Cannot read version\n');
  error(tt);
  return;
end;

header = struct();

i=1;
data = [];
kspace = [];
while(1)
    % Read number of (key, value) pairs contained in the header
    [hashcount, count] = fread(fip, 1, 'int');
    if (count ~= 1)
        fprintf(1,'Successfully read %d frames\n',i-1);
        break;
    end;

    % Read header
    for k=1:hashcount
        stringLength = fread(fip, 1, 'int');
        key = fread(fip, stringLength, '*char')';
        value = fread(fip, 1, 'double');
        header(i).(key) = value;
    end

    if (version >= 2)
        % Read kspace size
        [samples, count] = fread(fip, 1, 'int');
        if (count ~=1)
            tt = sprintf('Cannot read kspace size\n')
            error(tt);
            return;
        end;

        % Read kspace
	      kspace(:,:,i) = fread(fip, [1, samples], 'float');
    end


    if(isfield(header(i), 'dataSize'))
        dataSize = round(header(i).dataSize);
        % Read next block of data
        [tmpData, count] = fread(fip, [2,dataSize], 'float');
        if(count ~= 2*dataSize)
            fprintf(1,'End of file reached. Expected %d blocks of data but only read %d blocks.\n',dataSize,count);
            fprintf(1,'Successfully read %d frames\n',i-1);
            break;
        end;
        data(:,:,i) = tmpData;
    else
        % Read all remaining data
        [data, count] = fread(fip, [2,inf], 'float');

        % Print header
        header

        break;
    end

    i = i+1;
end

end

function table = getTable(fname)
    
    
    keyval = regexp(fname,'[^-_]*','match');
    table = cell2table(keyval(2:2:end),'VariableNames',keyval(1:2:end-1));
    
end

