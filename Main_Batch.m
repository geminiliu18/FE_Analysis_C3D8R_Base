% =========================================================================
% 重型热轧H型钢 轴心受压构件 批量参数化分析主程序 V4.0 (稳健监控与清理版)
% =========================================================================

clc; clear; close all;

% --- 0. 自动化路径与环境初始化 ---
main_dir = pwd; 
addpath(main_dir); 
root_dir = fileparts(main_dir); 

% 全局物理参数
E = 206000; nu = 0.3; fy = 355.0; 

% --- 1. 参数化输入配置区 ---
L_list = [3000, 6000, 9000, 12000, 15000]; 
section_files = {
    'Base_2D_H458.inp';
    'Base_2D_UC900.inp'
};

% --- 2. 任务看板初始化 ---
total_tasks = length(section_files) * length(L_list);
done_tasks = 0;
start_time = datetime('now');
error_log_file = fullfile(root_dir, 'Analysis_Error_Log.txt');

fprintf('======================================================\n');
fprintf('   轴心受压构件全自动稳定分析任务启动\n');
fprintf('   开始时间: %s\n', char(start_time));
fprintf('   总计任务数量: %d\n', total_tasks);
fprintf('======================================================\n\n');

% --- 3. 双层嵌套循环 ---
for s = 1:length(section_files)
    inp_name = section_files{s};
    [~, section_tag, ~] = fileparts(inp_name);
    inp_full_path = fullfile(main_dir, inp_name); 
    
    section_dir = fullfile(root_dir, section_tag);
    if ~exist(section_dir, 'dir'), mkdir(section_dir); end
    
    % 读取截面信息
    [nodes_2d, elems_2d] = func_ReadBase2D_INP(inp_full_path);
    mesh_z = func_CalculateMeshZ(nodes_2d, elems_2d, L_list);
    
    Section_Summary = zeros(length(L_list), 4);
    
    for l = 1:length(L_list)
        L = L_list(l);
        job_tag = sprintf('%s_L%d', section_tag, L);
        model_dir = fullfile(section_dir, sprintf('L%d', L));
        if ~exist(model_dir, 'dir'), mkdir(model_dir); end
        
        % 进度显示
        done_tasks = done_tasks + 1;
        elapsed_time = duration(datetime('now') - start_time);
        fprintf('[进度 %d/%d] 正在处理: %s\n', done_tasks, total_tasks, job_tag);
        fprintf('  已用时: %s | 剩余任务: %d\n', char(elapsed_time), total_tasks - done_tasks);

        % --- 稳健性核心：try-catch 结构 ---
        try
            cd(model_dir);
            
            % 1. 建模与 Buckle 求解
            [Nodes_3D, Elements_3D] = func_Extrude2Dto3D(nodes_2d, elems_2d, L, mesh_z);
            func_WriteAndSolve_Buckle(Nodes_3D, Elements_3D, L, E, nu, ['B_', job_tag]);
            
            % 2. 应力场与缺陷引入
            num_elem_layers = round(L / mesh_z);
            Stress_Matrix = func_GenerateStressField(nodes_2d, elems_2d, num_elem_layers, fy);
            Nodes_imperfect = func_IntroduceImperfection(Nodes_3D, ['B_', job_tag, '.dat'], L/1000);
            
            % 3. Riks 极值分析
            tol = 1e-5;
            bottom_nodes = Nodes_3D(abs(Nodes_3D(:, 4) - 0) < tol, 1);
            top_nodes    = Nodes_3D(abs(Nodes_3D(:, 4) - L) < tol, 1);
            func_WriteAndSolve_Riks(Nodes_imperfect, Elements_3D, Stress_Matrix, ...
                                    bottom_nodes, top_nodes, L, E, nu, ['R_', job_tag]);
            
            % 4. 后处理提取
            [p_max, s_max] = func_QuickExtract_Riks(['R_', job_tag, '.dat'], inp_full_path);
            Section_Summary(l, :) = [L, p_max, s_max, mesh_z];
            
            % 5. 自动清理临时文件 (保留核心文件：.inp, .dat, .odb)
            % 定义需要清理的扩展名列表
            clean_exts = {'.com', '.log', '.msg', '.sta', '.stt', '.res', '.mdl', '.sel', '.abq', '.pac', '.lck', '.sim', '.prt'};
            for e = 1:length(clean_exts)
                delete(['*', clean_exts{e}]); 
            end
            fprintf('  > 运算成功并已清理临时文件。\n\n');

        catch ME
            % 记录错误信息到日志
            fid_err = fopen(error_log_file, 'a');
            fprintf(fid_err, '[%s] 错误模型: %s\n', char(datetime('now')), job_tag);
            fprintf(fid_err, '错误原因: %s\n\n', ME.message);
            fclose(fid_err);
            
            warning('  [!] 模型 %s 运算失败，已跳过。详细信息见错误日志。\n\n', job_tag);
            Section_Summary(l, :) = [L, NaN, NaN, mesh_z]; % 标记为无效数据
            continue; % 继续下一个长度的运算
        end
    end
    
    % 导出当前截面的汇总数据
    cd(section_dir);
    T = table(Section_Summary(:,1), Section_Summary(:,2), Section_Summary(:,3), Section_Summary(:,4), ...
        'VariableNames', {'Length_L_mm', 'Ultimate_Load_N', 'Ultimate_Stress_MPa', 'Mesh_Z_mm'});
    writetable(T, ['Result_Summary_', section_tag, '.xlsx']);
end

cd(main_dir);
fprintf('======================================================\n');
fprintf('   任务全部完成！\n');
fprintf('   总耗时: %s\n', char(duration(datetime('now') - start_time)));
fprintf('======================================================\n');