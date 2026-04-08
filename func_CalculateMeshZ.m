function mesh_z = func_CalculateMeshZ(nodes_2d, elems_2d, L_list)
% 基于 2D 截面特征与长度整除要求自动计算 Z 向步长

    % 1. 寻找 2D 截面的最小边长 d_min
    % elems_2d 格式: [ID, n1, n2, n3, n4]
    min_d = inf;
    for i = 1:size(elems_2d, 1)
        node_ids = elems_2d(i, 2:5);
        p = nodes_2d(node_ids, 2:3); % 提取 X, Y
        
        % 计算 4 条边的长度
        dists = [norm(p(1,:) - p(2,:));
                 norm(p(2,:) - p(3,:));
                 norm(p(3,:) - p(4,:));
                 norm(p(4,:) - p(1,:))];
        min_d = min([min_d; dists]);
    end
    
    % 2. 计算原则: 不大于 3*min_d 的最大的 5 的倍数
    target_z = floor((3 * min_d) / 5) * 5;
    if target_z < 5, target_z = 5; end % 兜底
    
    % 3. 满足整除性约束
    % 如果 target_z 不能整除 L_list 中的所有长度，则向下寻找最近的 5 的倍数
    mesh_z = target_z;
    while mesh_z >= 5
        check = mod(L_list, mesh_z);
        if all(check == 0)
            break;
        else
            mesh_z = mesh_z - 5;
        end
    end
    
    if mesh_z == 0, mesh_z = 5; end % 理论上由于 L 是 5 的倍数，最终至少会返回 5
end