local _M = {}
local bit = require "bit"
local cjson = require "cjson.safe"
local Json = cjson.encode

local strload

--Json的Key，用于通用数据帧
local cmds = {
    [0] = "length",     --数据包长度
    [1] = "DTU_time",   --DTU运行时间
    [2] = "DTU_status", --DTU状态
    [3] = "DTU_function",   --DTU功能码
    [4] = "fcs_status"       --数据包FCS结果
}

--Json的Key，用于故障
local fault_cmds = {
    "code","level","status",
    "year","month","day","hour","min","sec"
}

--配合my_cmds使用，指出sys_,limit_,in_,on_,fall_,confeedback_和conoutput_的个数
local data_bit_count = {
    [1] = {Byte_name = "X0", bit_count =  1, data_index1 = 18, data_index2 = 19},
    [2] = {Byte_name = "X1", bit_count = 10, data_index1 = 20, data_index2 = 21},
    [3] = {Byte_name = "X2", bit_count =  8, data_index1 = 22, data_index2 = 23},
    [4] = {Byte_name = "X3", bit_count =  6, data_index1 = 24, data_index2 = 25},
    [5] = {Byte_name = "X4", bit_count =  3, data_index1 = 26, data_index2 = 27},
    [6] = {Byte_name = "XA", bit_count =  4, data_index1 = 28, data_index2 = 29},
    
    [7] = {Byte_name = "X0_POL", bit_count =  1, data_index1 = 30, data_index2 = 31},
    [8] = {Byte_name = "X1_POL", bit_count = 10, data_index1 = 32, data_index2 = 33},
    [9] = {Byte_name = "X2_POL", bit_count =  8, data_index1 = 34, data_index2 = 35},
    [10] = {Byte_name = "X3_POL", bit_count = 6, data_index1 = 36, data_index2 = 37},
    [11] = {Byte_name = "X4_POL", bit_count = 3, data_index1 = 38, data_index2 = 39},
    [12] = {Byte_name = "XA_POL", bit_count = 4, data_index1 = 40, data_index2 = 41},
    
    [13] = {Byte_name = "pub_command_in", bit_count = 4,        data_index1 = 42, data_index2 = 43},--公共命令输入
    [14] = {Byte_name = "rise_command_in", bit_count = 3,       data_index1 = 44, data_index2 = 45},--起升命令输入
    [15] = {Byte_name = "car_command_in", bit_count = 5,        data_index1 = 46, data_index2 = 47},--小车命令输入
    [16] = {Byte_name = "pull_limit_signal", bit_count = 3,     data_index1 = 48, data_index2 = 49},--限位信号
    [17] = {Byte_name = "feedback_signal", bit_count = 9,       data_index1 = 50, data_index2 = 51},--反馈信号
    [18] = {Byte_name = "relay_output_status", bit_count = 8,   data_index1 = 56, data_index2 = 57},--继电器输出状态
    [19] = {Byte_name = "Y2_output", bit_count = 3,             data_index1 = 58, data_index2 = 59},--Y2端子排输出
    [20] = {Byte_name = "sys_comm_output_signal", bit_count = 1,        data_index1 = 62, data_index2 = 63},--系统公共输出信号
    [21] = {Byte_name = "improve_control_output_signal", bit_count = 4, data_index1 = 64, data_index2 = 65},--提升控制输出信号
    [22] = {Byte_name = "car_control_output_signal", bit_count = 5,     data_index1 = 66, data_index2 = 67},--小车控制输出信号
}

--将字符转换为数字
function getnumber(index)
   return string.byte(strload,index)
end

function get_one_word(index1, index2)
    return (bit.lshift( getnumber(18), 8 ) + getnumber(19))
end

--FCS校验
function utilCalcFCS(pBuf, len)
    local rtrn = 0
    local l = len

    while (len ~= 0)
    do
        len = len - 1
        rtrn = bit.bxor(rtrn , pBuf[l-len])
    end

    return rtrn
end

function packet_fcs(templen)
    local FCS_Array = {}    --FCS校验的数组(table)，用于逐个存储每个Byte的数值
    local FCS_Value = 0     --用来直接读取发来的数值，并进行校验

	FCS_Value = bit.lshift( getnumber(templen + 5), 8 ) + getnumber(templen + 6) --得到FCS校验
    
    for i = 1,templen + 4,1 do
        table.insert(FCS_Array,getnumber(i))
    end
    
    --进行FCS校验，如果计算值与读取指相等，则此包数据有效;否则弃之
    if(utilCalcFCS(FCS_Array,#FCS_Array) == FCS_Value) then
        return true
    else
        return false
    end
end

function status_packet_init()
    packet["sys_status"] = bit.lshift( getnumber(12), 8 ) + getnumber(13)  --设备系统状态     0:待机 1:停止 2:就绪
    packet["lft_status"] = bit.lshift( getnumber(14), 8 ) + getnumber(15)  --机构起升状态     0: 停止 1: 正转低速 2: 正转高速 3: 反转低速 4: 反转高速
    packet["car_status"] = bit.lshift( getnumber(16), 8 ) + getnumber(17)  --小车状态             0: 停止 1: 停车中 2: 正转低速 3: 反转低速 4: 正转高速 5: 反转高速
    packet["lastest_malfunction_code"] = bit.lshift( getnumber(52), 8 ) + getnumber(53) --最近一个故障代码
    packet["carrying_capacity"] = (bit.lshift( getnumber(54), 8 ) + getnumber(55))/100  --载重 (两位小数 单位:吨)
    
    for var=1, #data_bit_count do
        for j=1, data_bit_count[var].bit_count do
            local packet_data = get_one_word(data_bit_count[var].data_index1, get_one_word(data_bit_count[var].data_index2))
            
            if(bit.band(packet_data, bit.lshift(1,j - 1))) then 
        	   packet[(data_bit_count[var].Byte_name).."_BIT"..(j-1)] = "Y"
        	else
        	   packet[(data_bit_count[var].Byte_name).."_BIT"..(j-1)] = "N"
        	end  
        	
        end
    end
    
end

function fault_packet_int(fault_total)

    for i=1,fault_total * 9,1 do
        local n = ((i-1) % 9)+1
        local m = math.ceil(i/9)
        packet[ "fault"..m..fault_cmds[n] ] = bit.lshift( getnumber(14+i*2) , 8 ) + getnumber(15+i*2)
        if i % 9 == 0 then
            packet[ "fault"..m.."time" ] = packet["fault"..m.."year"]..'/'..packet["fault"..m.."month"]..'/'..packet["fault"..m.."day"]..'-'..packet["fault"..m.."hour"]..':'..packet["fault"..m.."min"]..':'..packet["fault"..m.."sec"]
--            table.remove(packet,"fault"..m.."year");
--            table.remove(packet,"fault"..m.."month");
--            table.remove(packet,"fault"..m.."day");
--            table.remove(packet,"fault"..m.."hour");
--            table.remove(packet,"fault"..m.."min");
--            table.remove(packet,"fault"..m.."sec");
        end
    end
end




--将字符转换为数字
function getnumber( index )
    return string.byte(strload,index)
end

--编码 /in 频道的数据包
function _M.encode(payload)
  return payload
end


--解码 /out 频道的数据包
function _M.decode(payload)
    strload = payload       --strload是全局变量，唯一的作用是在getnumber函数中使用
    
    local packet = {['status']='not'} --有一个status的初始值
    local packet_for_bit = {}
    
    local head1 = getnumber(1)  --前2个Byte是帧头，正常情况应该为';'和'1'
    local head2 = getnumber(2)
    
    if ( head1 ~= 0x3B or head2 ~= 0x31 ) then --如果数据包头部不是0x3B和0x31,则数据包错误
        return Json(packet) 
    end
    
    local templen = bit.lshift( getnumber(3) , 8 ) + getnumber(4) --获取数据包的长度
    
    if(packet_fcs(templen) == true) then
        packet[cmds[4]] = 'FCS_SUCCESS'
    else
        packet[cmds[4]] = 'FCS_ERROR'
        return Json(packet) 
    end
    
    --数据长度
    packet[ cmds[0] ] = templen
    --运行时长
    packet[ cmds[1] ] = bit.lshift( getnumber(5) , 8 ) + bit.lshift( getnumber(6) , 16 ) + bit.lshift( getnumber(7) , 8 ) + getnumber(8)

    --模式
    local mode = getnumber(9)

    if mode == 1 then
        packet[ cmds[2] ] = 'Mode-485'
    elseif mode == 2 then
        packet[ cmds[2] ] = 'Mode-232'
    else
        packet[ cmds[2] ] = 'Mode-ERROR'
        return Json(packet) 
    end
    
    local func = getnumber(10)  --func为判断是 实时数据/参数/故障 的参数
    
    if (func == 1) then --状态数据包处理>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        packet[ cmds[3] ] = 'func-status'
     
        status_packet_init();
        
    elseif (func == 2) then --故障数据包处理>>>>>>>>>>>>>>>>>>>>>>>>
        packet[ cmds[3] ] = 'func-fault'
                    
        local fault_total = bit.lshift( getnumber(12),8) + getnumber(13)
        packet[ "fault_total" ] = fault_total
        
        fault_packet_int(fault_total);
      
    else --其他类型数据包处理>>>>>>>>>>>>>>>>>>>>>
        packet[ cmds[3] ] = 'func-error'
    end
    
    return Json(packet)
end

return _M

--print(_M.decode(string.fromhex('aa0010050102030405060708090a051e051e0101010101010101010101010101')))










