function dat2BIDS3(datDir)


datList = dir(fullfile(datDir,'*.dat'));
if ~exist([datDir filesep 'converted'], 'dir'); mkdir([datDir filesep 'converted']); end
lookup = json2struct('suffix2folder.json');


for ii = 1:length(datList)
    
  details = getDetails(datList(ii).name,lookup);
  
  if ~isempty(details.ses)
      curFolder = cell2mat(['sub-' details.sub filesep 'ses-' details.ses filesep details.folder]);
  else
      curFolder = cell2mat(['sub-' details.sub filesep details.folder]);
  end
  
  if ~exist(curFolder, 'dir')
      mkdir(curFolder);
  end
  
  %curFolder = pwd;
  exportBIDS(datDir,datList(ii).name,curFolder);
  
end




end


%
% loadRthData.m
% Read data and header from the file exported by RTHawk
% This can take several minutes if the files are big
%
%     input: fileName -- the name of the file to which data have
%                        been exported using RthReconImageExport.cpp
%     output: data -- the image data
%             header -- the image data header
%             kspace -- the acquisition trajectory (kx ky density
%                       for each sample)
%

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

  if version > 3
      header = [];
  else
      header = struct();
  end

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

      if version > 3
          headerData = char(fread(fip, hashcount, '*char'));
          header = [header, jsondecode(convertCharsToStrings(headerData))];
	 else
          % Read header
          for k=1:hashcount
              stringLength = fread(fip, 1, 'int');
              key = fread(fip, stringLength, '*char')';
              value = fread(fip, 1, 'double');
              header(i).(key) = value;
          end
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


function out = getDetails(fname,lookup)
    
    out = struct();
    out.sub = regexp(fname,'(?<=sub-).*?(?=_)','match');
    out.ses = regexp(fname,'(?<=ses-).*?(?=_)','match');
    out.suffix = regexp(fname,'(?!.*_).*?(?=.dat)','match');
    out.folder = suffixToFolder(out.suffix,lookup);
    
end


function folderName = suffixToFolder(suffix,lookup)


if ismember(suffix,cellstr(lookup.anat))
    folderName = 'anat';
elseif ismember(suffix,cellstr(lookup.fmap))
    folderName = 'fmap';
else
    folderName = 'unknown';
end

end

function exportBIDS(datDir,fname,svdir)
% Kspace data ends with raw.dat. qMRPullseq convention. In that case, 
% ISMRM-RD will be exported. BIDS (image) otherwise. 

if isempty(regexp(fname,'.*?(?=raw.dat)'))
        
        [data, header] = loadDat([datDir filesep fname]);

        data = data(1,:) + 1i*data(2,:);

        data = reshape(data,[header.extent(1),header.extent(2),header.extent(3)]);
                
        % DICOM's coordinate system is 180 degrees rotated about the z-axis
        % from the neuroscience/NIFTI coordinate system.
        R = qGetR([header.geometry_QuaternionW,header.geometry_QuaternionX,header.geometry_QuaternionY,header.geometry_QuaternionZ]);
        orderCheck = abs(round(R));
        
        % Infer scan (order) plane.
        if isequal(orderCheck,[1 0 0;0 1 0;0 0 1]) % axial
            % Flip along Y 
            data = flip(data,2);
            tX = header.geometry_TranslationX;
            tY = header.geometry_TranslationY;
            tZ = header.geometry_TranslationZ;
        elseif isequal(orderCheck,[1 0 0;0 0 1;0 1 0]) % coronal
            % Flip along X
            data = flip(data,1);
            tX = header.geometry_TranslationX;
            tY = header.geometry_TranslationZ;
            tZ = header.geometry_TranslationY;
        elseif isequal(orderCheck,[0 0 1;1 0 0;0 1 0]) % sagittal
            % Flip along Z
            tX = header.geometry_TranslationZ;
            tY = header.geometry_TranslationX;
            tZ = header.geometry_TranslationY;
            data = flip(data,3);
        else % simulator
            tX = 0;
            tY = 0;
            tZ = 0;
        end
        
        nii = make_nii(data, [header.mri_VoxelSpacing(1) header.mri_VoxelSpacing(2) header.mri_VoxelSpacing(3)], [tX tY tZ], 64);    
              
        nii.hdr.hist.qform_code = 1;
        nii.hdr.hist.sform_code = 0;
        nii.hdr.hist.quatern_b = header.geometry_QuaternionX;
        nii.hdr.hist.quatern_c = header.geometry_QuaternionY;
        nii.hdr.hist.quatern_d = header.geometry_QuaternionZ;
        
        nii.hdr.hist.qoffset_x = tX;
        nii.hdr.hist.qoffset_y = tY;
        nii.hdr.hist.qoffset_z = tZ;
        
        qfac = 1;
        i = header.mri_VoxelSpacing(1);
        j = header.mri_VoxelSpacing(2);
        k = qfac * header.mri_VoxelSpacing(3);
        
        

         T = [nii.hdr.hist.qoffset_x
           nii.hdr.hist.qoffset_y
           nii.hdr.hist.qoffset_z];

        nii.hdr.hist.old_affine = [ [R * diag([i j k]);[0 0 0]] [T;1] ];
        
        save_nii(nii,[svdir filesep fname(1:end-4) '.nii.gz']);
        header = cleanHeader(header);
        savejson('',header,[svdir filesep fname(1:end-4) '.json']);
        
        % Move converted file to another directory.
        movefile([datDir filesep fname],[datDir filesep 'converted' filesep fname]);
end


end

function newHeader = cleanHeader(header)

    fields = fieldnames(header);
    newHeader =struct;
    
    for ii=1:length(fields)
        curField = fields{ii};
        loc = strfind(curField,'_');
        if ~isempty(loc)
            loc = min(loc);
            newHeader.(curField(loc+1:end)) = header.(curField);
        else
            newHeader.(curField) = header.(curField);
        end
          
    end
    
end
