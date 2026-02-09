--!ARM Embedded Hardware Test Rule
--
-- Rule for creating embedded tests that run on actual hardware or simulators
--

rule("embedded.test")
    -- Inherit from embedded rule
    add_deps("embedded")
    
    on_load(function(target)
        -- Mark as test target
        target:set("group", "test")
        
        -- Don't build by default
        if target:get("default") == nil then
            target:set("default", false)
        end
        
        -- Mark as embedded test
        target:data_set("is_embedded_test", true)
        
        -- Add test framework support
        local test_framework = target:values("embedded.test_framework")
        if test_framework == "unity" then
            -- Unity is lightweight and suitable for embedded
            target:add("defines", "UNITY_INCLUDE_CONFIG_H")
        elseif test_framework == "minunit" then
            -- Minimal unit testing
            target:add("defines", "MINUNIT_TESTS")
        end
    end)
    
    on_run(function(target)
        import("core.project.task")
        
        local test_mode = target:values("embedded.test_mode") or "hardware"
        
        if test_mode == "hardware" then
            -- Flash to hardware and monitor output
            print("Running embedded test on hardware: " .. target:name())
            
            -- Flash the test binary
            task.run("flash", {target = target:name()})
            
            -- Monitor serial output for test results
            local serial_port = target:values("embedded.test_serial")
            local baudrate = target:values("embedded.test_baudrate") or 115200
            local timeout = target:values("embedded.test_timeout") or 30
            
            if serial_port then
                print("Monitoring serial port " .. serial_port .. " @ " .. baudrate .. " baud")
                -- Simple serial monitor (would need pyserial or similar)
                local monitor_cmd = string.format([[
                    python3 -c "
import serial
import sys
import time

ser = serial.Serial('%s', %d, timeout=%d)
start_time = time.time()
test_passed = False

while time.time() - start_time < %d:
    if ser.in_waiting:
        line = ser.readline().decode('utf-8').strip()
        print(line)
        if 'TESTS PASSED' in line:
            test_passed = True
            break
        elif 'TESTS FAILED' in line:
            sys.exit(1)

if not test_passed:
    print('Test timeout')
    sys.exit(1)
"
                ]], serial_port, baudrate, timeout, timeout)
                
                local ok = try { function()
                    os.exec(monitor_cmd)
                    return true
                end }
                
                if not ok then
                    raise("Embedded test failed")
                end
            else
                print("Warning: No serial port specified for test monitoring")
                print("Test flashed successfully, but results cannot be verified")
            end
            
        elseif test_mode == "qemu" then
            -- Run in QEMU emulator
            print("Running embedded test in QEMU: " .. target:name())
            
            local mcu = target:values("embedded.mcu")
            local qemu_machine = get_qemu_machine_for_mcu(mcu)
            
            if not qemu_machine then
                raise("QEMU does not support MCU: " .. (mcu and mcu[1] or "unknown"))
            end
            
            local qemu_cmd = string.format(
                "qemu-system-arm -M %s -nographic -kernel %s -semihosting",
                qemu_machine,
                target:targetfile()
            )
            
            print("QEMU command: " .. qemu_cmd)
            os.exec(qemu_cmd)
            
        elseif test_mode == "renode" then
            -- Run in Renode emulator
            print("Running embedded test in Renode: " .. target:name())

            -- Check for explicit script first, then auto-generate from MCU database
            local renode_script = target:values("embedded.test_renode_script")
            if renode_script then
                if type(renode_script) == "table" then renode_script = renode_script[1] end
                os.exec("renode --console --disable-xwt " .. renode_script)
            else
                -- Auto-generate CI .resc from MCU database
                import("core.base.json")
                local mcu_data = target:data("embedded._mcu_data")
                local mcu = target:values("embedded.mcu")
                local mcu_name = mcu and (type(mcu) == "table" and mcu[1] or mcu) or nil
                local mcu_config = nil
                if mcu_name and mcu_data and mcu_data.CONFIGS then
                    mcu_config = mcu_data.CONFIGS[mcu_name:lower()]
                end

                if not mcu_config or not mcu_config.renode_repl then
                    raise("Renode not supported for MCU: " .. (mcu_name or "unknown")
                          .. ". Add renode_repl to mcu-database.json or set embedded.test_renode_script")
                end

                local repl_path = mcu_config.renode_repl
                local flash_origin = mcu_config.flash_origin or "0x08000000"
                local flash_origin_plus4 = string.format("0x%08X", tonumber(flash_origin) + 4)
                local target_name = target:name()
                local target_dir = path.join("build", target_name, "release")
                local timeout = target:values("embedded.test_timeout") or 2

                local resc_content = table.concat({
                    "# Auto-generated Renode CI test script",
                    "",
                    "using sysbus",
                    "",
                    'mach create "' .. target_name .. '_ci"',
                    "",
                    "machine LoadPlatformDescription $CWD/" .. repl_path,
                    "sysbus LoadELF $CWD/" .. target_dir .. "/" .. target_name .. ".elf",
                    "",
                    "sysbus WriteDoubleWord 0xE000ED08 " .. flash_origin,
                    "sysbus WriteDoubleWord 0x00000000 `sysbus ReadDoubleWord " .. flash_origin .. "`",
                    "sysbus WriteDoubleWord 0x00000004 `sysbus ReadDoubleWord " .. flash_origin_plus4 .. "`",
                    "",
                    "usart1 CreateFileBackend $CWD/" .. target_dir .. "/uart.log true",
                    "",
                    "cpu PerformanceInMips 100",
                    'emulation RunFor "' .. timeout .. '"',
                    "",
                    "usart1 CloseFileBackend $CWD/" .. target_dir .. "/uart.log",
                    "quit",
                    "",
                }, "\n")

                local resc_path = path.join(target_dir, target_name .. "_ci.resc")
                os.mkdir(target_dir)
                io.writefile(resc_path, resc_content)

                os.execv("renode", {"--console", "--disable-xwt", resc_path})
            end
            
        else
            raise("Unknown embedded test mode: " .. test_mode)
        end
    end)
    
    -- Helper function to map MCU to QEMU machine
    function get_qemu_machine_for_mcu(mcu)
        local mcu_name = mcu and (type(mcu) == "table" and mcu[1] or mcu) or ""
        
        -- Common mappings
        local qemu_machines = {
            ["stm32f407vg"] = "netduinoplus2",
            ["stm32f405rg"] = "netduino2",
            ["stm32f103c8"] = "stm32vldiscovery",
            ["lpc1768"] = "lpc1768",
            ["nrf52832"] = "microbit",
            ["nrf52840"] = "microbit-v2"
        }
        
        return qemu_machines[mcu_name:lower()]
    end
    
    before_build(function(target)
        -- Add test-specific defines
        target:add("defines", "EMBEDDED_TEST")
        
        -- Configure test output method
        local output_method = target:values("embedded.test_output") or "semihosting"
        
        if output_method == "semihosting" then
            -- ARM semihosting for output
            target:add("defines", "USE_SEMIHOSTING")
            target:add("ldflags", "--specs=rdimon.specs", "-lrdimon")
        elseif output_method == "rtt" then
            -- SEGGER RTT for output
            target:add("defines", "USE_RTT")
        elseif output_method == "uart" then
            -- UART for output
            target:add("defines", "USE_UART_OUTPUT")
        end
        
        -- Add timeout mechanism
        local timeout = target:values("embedded.test_timeout")
        if timeout then
            target:add("defines", "TEST_TIMEOUT_MS=" .. (timeout * 1000))
        end
    end)