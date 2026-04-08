function [nodes_2d, elems_2d] = func_ReadBase2D_INP(filename)
% FUNC_READBASE2D_INP 解析 Abaqus 2D 截面网格的 INP 文件
% 
% 输入参数:
%   filename: INP 文件名 (例如 'Base_2D.inp')
% 输出参数:
%   nodes_2d: 2D节点矩阵 [NodeID, X, Y]
%   elems_2d: 2D单元矩阵 [ElemID, n1, n2, n3, n4]

    % 打开文件
    fid = fopen(filename, 'r');
    if fid == -1
        error('[Error] 无法打开文件: %s，请检查路径或文件名。', filename);
    end

    % 初始化输出
    nodes_2d = [];
    elems_2d = [];
    
    % 状态标记
    current_section = 'None'; 

    while ~feof(fid)
        % 读取一行并去除首尾空格
        line = strtrim(fgetl(fid));
        
        % 跳过空行和注释行
        if isempty(line) || startsWith(line, '**')
            continue;
        end
        
        % 识别关键字
        if startsWith(line, '*', 'IgnoreCase', true)
            if startsWith(line, '*Node', 'IgnoreCase', true)
                current_section = 'Node';
            elseif startsWith(line, '*Element', 'IgnoreCase', true)
                current_section = 'Element';
            else
                current_section = 'Other'; % 其他无关关键字，如 *Heading 等
            end
            continue;
        end
        
        % 提取数据
        if strcmp(current_section, 'Node')
            % 解析逗号分隔的数字
            data = sscanf(line, '%f,')';
            if length(data) >= 3
                % 只取前三列：ID, X, Y (忽略可能存在的 Z=0 坐标)
                nodes_2d = [nodes_2d; data(1:3)]; %#ok<AGROW>
            end
        elseif strcmp(current_section, 'Element')
            data = sscanf(line, '%f,')';
            if length(data) >= 5
                % 取前五列：ID, n1, n2, n3, n4
                elems_2d = [elems_2d; data(1:5)]; %#ok<AGROW>
            end
        end
    end
    
    fclose(fid);
end