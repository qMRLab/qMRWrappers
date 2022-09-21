num_subjects = 6;
num_sessions = 10;

%masks = {'_label-GM_MP2RAGE', '_label-WM_MP2RAGE'};
%maps = {'_acq-MP2RAGE_T1map'};

masks = {'_label-GM_MTS', '_label-WM_MTS'};
maps = {'_MTRmap', '_acq-MTS_MTsat', '_acq-MTS_T1map'};

mapList = {};
maskList = {};
for ii = 1:num_subjects
    for jj = 1:num_sessions
        if jj>9
            ses = ['0' num2str(jj)];
        else
            ses = ['00' num2str(jj)];
        end
        for kk = 1:length(masks)
            tmp =['sub-0' num2str(ii) '/ses-' ses '/anat/' 'sub-0' num2str(ii) '_ses-' ses masks{kk} '.nii.gz'];
            if isfile(tmp)
                maskList{end+1}=tmp;
            end
        end
        for kk = 1:length(maps)
            tmp = ['sub-0' num2str(ii) '/ses-' ses '/anat/' 'sub-0' num2str(ii) '_ses-' ses maps{kk} '.nii.gz'];
            if isfile(tmp)
                mapList{end+1}=tmp;
            end
        end
    end
end

disp(mapList)
disp(maskList)