function [max_force, max_stress] = func_QuickExtract_Riks(dat_file, inp_file)
% 快速读取 Riks 的 .dat 文件，返回标量极值

    % (1) 先获取面积 (用于应力换算)
    [nodes_2d, elems_2d] = func_ReadBase2D_INP(inp_file);
    area = 0;
    for i = 1:size(elems_2d, 1)
        n_idx = elems_2d(i, 2:5);
        x = nodes_2d(n_idx, 2); y = nodes_2d(n_idx, 3);
        % 鞋带公式
        area = area + 0.5 * abs((x(1)*y(2)-y(1)*x(2)) + (x(2)*y(3)-y(2)*x(3)) + ...
                                (x(3)*y(4)-y(3)*x(4)) + (x(4)*y(1)-y(4)*x(1)));
    end

    % (2) 提取反力 RF3
    fid = fopen(dat_file, 'r');
    if fid == -1, error('File not found: %s', dat_file); end
    
    RF3_all = [];
    is_reading = false;
    while ~feof(fid)
        line = fgetl(fid);
        if contains(line, 'NODE FOOT-') && contains(line, 'RF3')
            is_reading = true; continue;
        end
        if is_reading
            tline = strtrim(line);
            if ~isempty(tline) && isstrprop(tline(1), 'digit')
                data = sscanf(tline, '%f');
                if length(data) >= 3
                    RF3_all = [RF3_all; abs(data(3))];
                    is_reading = false;
                end
            end
        end
    end
    fclose(fid);
    
    if isempty(RF3_all)
        max_force = NaN; max_stress = NaN;
    else
        max_force = max(RF3_all);
        max_stress = max_force / area;
    end
end