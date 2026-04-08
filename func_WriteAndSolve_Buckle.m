function func_WriteAndSolve_Buckle(Nodes_3D, Elements_3D, L, E, nu, jobName)
% FUNC_WRITEANDSOLVE_BUCKLE 生成无残余应力的Buckle模型并静默求解
% 已更新: 修复 Abaqus INP 文件 NSET 数据行最多 16 个字符的限制

    % --- 1. 端部节点集 (NSET) 自动提取 ---
    tol = 1e-5; % 坐标容差
    bottom_nodes = Nodes_3D(abs(Nodes_3D(:, 4) - 0) < tol, 1);
    top_nodes    = Nodes_3D(abs(Nodes_3D(:, 4) - L) < tol, 1);
    
    max_node_id = max(Nodes_3D(:, 1));
    rp_bottom_id = max_node_id + 1;
    rp_top_id    = max_node_id + 2;
    
    % --- 2. 编写 .inp 文件 ---
    inp_filename = [jobName, '.inp'];
    fid = fopen(inp_filename, 'w');
    if fid == -1
        error('无法创建或打开 INP 文件。');
    end
    
    fprintf(fid, '*Heading\n');
    fprintf(fid, '** Job name: %s\n', jobName);
    fprintf(fid, '*Preprint, echo=NO, model=NO, history=NO, contact=NO\n');
    
    % (1) 实体节点写入
    fprintf(fid, '*Node\n');
    fprintf(fid, '%d, %.6f, %.6f, %.6f\n', Nodes_3D');
    
    % (2) Reference Points
    fprintf(fid, '** Reference Points\n');
    fprintf(fid, '%d, 0.0, 0.0, 0.0\n', rp_bottom_id);
    fprintf(fid, '%d, 0.0, 0.0, %.6f\n', rp_top_id, L);
    
    % (3) 单元写入 (C3D8I)
    fprintf(fid, '*Element, type=C3D8I, elset=All_Elements\n');
    fprintf(fid, '%d, %d, %d, %d, %d, %d, %d, %d, %d\n', Elements_3D');
    
    % (4) 定义节点集 (修复 16 项限制的核心逻辑)
    % 写入 Bottom_Nodes
    fprintf(fid, '*Nset, nset=Bottom_Nodes\n');
    for i = 1:length(bottom_nodes)
        if mod(i, 16) == 0 || i == length(bottom_nodes)
            fprintf(fid, '%d\n', bottom_nodes(i));
        else
            fprintf(fid, '%d, ', bottom_nodes(i));
        end
    end
    
    % 写入 Top_Nodes
    fprintf(fid, '*Nset, nset=Top_Nodes\n');
    for i = 1:length(top_nodes)
        if mod(i, 16) == 0 || i == length(top_nodes)
            fprintf(fid, '%d\n', top_nodes(i));
        else
            fprintf(fid, '%d, ', top_nodes(i));
        end
    end
    
    fprintf(fid, '*Nset, nset=RP_Bottom\n');
    fprintf(fid, '%d\n', rp_bottom_id);
    
    fprintf(fid, '*Nset, nset=RP_Top\n');
    fprintf(fid, '%d\n', rp_top_id);
    
    % 提取所有实体节点
    fprintf(fid, '*Nset, nset=All_Nodes, generate\n');
    fprintf(fid, '%d, %d, 1\n', min(Nodes_3D(:,1)), max(Nodes_3D(:,1)));
    
    % (5) 表面与耦合
    fprintf(fid, '** Define node-based surfaces for coupling\n');
    fprintf(fid, '*Surface, type=NODE, name=Bottom_Surf\n');
    fprintf(fid, 'Bottom_Nodes, 1.0\n');
    fprintf(fid, '*Surface, type=NODE, name=Top_Surf\n');
    fprintf(fid, 'Top_Nodes, 1.0\n');
    
    fprintf(fid, '** Kinematic Coupling\n');
    fprintf(fid, '*Coupling, constraint name=Coupling-Bottom, ref node=RP_Bottom, surface=Bottom_Surf\n');
    fprintf(fid, '*Kinematic\n');
    fprintf(fid, '1, 6\n');
    
    fprintf(fid, '*Coupling, constraint name=Coupling-Top, ref node=RP_Top, surface=Top_Surf\n');
    fprintf(fid, '*Kinematic\n');
    fprintf(fid, '1, 6\n');
    
    % (6) 材料
    fprintf(fid, '*Solid Section, elset=All_Elements, material=Steel\n');
    fprintf(fid, ',\n');
    fprintf(fid, '*Material, name=Steel\n');
    fprintf(fid, '*Elastic\n');
    fprintf(fid, '%.2f, %.3f\n', E, nu);
    fprintf(fid, '*Plastic\n');
    fprintf(fid, '355.0, 0.0\n');
    
    % --- 3. 分析步与载荷 ---
    fprintf(fid, '*Step, name=Buckle_Step, nlgeom=NO\n');
    fprintf(fid, '*Buckle\n');
    fprintf(fid, '3, , , \n'); 
    
    fprintf(fid, '*Boundary\n');
    fprintf(fid, 'RP_Bottom, 1, 3\n');
    fprintf(fid, 'RP_Bottom, 6, 6\n');
    fprintf(fid, 'RP_Top, 1, 2\n');
    fprintf(fid, 'RP_Top, 6, 6\n');
    
    fprintf(fid, '*Cload\n');
    fprintf(fid, 'RP_Top, 3, -1.0\n');
    
    % --- 4. 输出请求 ---
    fprintf(fid, '*Output, field\n');
    fprintf(fid, '*Node Output\n');
    fprintf(fid, 'U\n');
    
    fprintf(fid, '*Node Print, nset=All_Nodes, freq=1\n');
    fprintf(fid, 'U1, U2, U3\n');
    
    fprintf(fid, '*End Step\n');
    fclose(fid);
    
    % --- 5. 静默求解 ---
    disp(['[Solve A] 正在提交 Abaqus 求解: ', jobName, ' ...']);
    cmd = sprintf('abaqus job=%s cpus=8 interactive ask_delete=OFF', jobName);
   status = system(cmd);
    
    if status == 0
        disp('[Solve A] Buckle 求解完成，.dat 文件已生成。');
   else
       error('[Solve A] Abaqus 求解失败，请检查 .msg 或 .dat 文件中的报错信息。');
   end

end