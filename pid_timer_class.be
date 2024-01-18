import json
import mqtt

var hot_relay = 1 #relay number for the hot side peltier cooler
var cold_relay = 2 #relay number for the cold side peltier cooler
var hot_cooler_timer
var cold_cooler_timer



def resetable_timer(millis, f)
    #https://github.com/arendst/Tasmota/discussions/16704?sort=new
    class _resetable_timer
      var millis
      def init(millis)
        self.millis = millis
        self.reset()
      end
      def reset()
        self.clear()
        tasmota.set_timer(self.millis, f, self)
      end
      def clear()
        tasmota.remove_timer(self)
      end
    end
    return _resetable_timer(millis)
end

def setpoint_change(topic, idx, strdata, bindata)
    print ("MQTT topic -> ", topic, "data: ", strdata)  
    #Sp = int(strdata)  
    return true
end

def start_cold_cooler()
    print("Timer: Starting Cold Cooler")   
    tasmota.set_power(cold_relay, true)    
end

def stop_hot_cooler()
    print("Timer: Stopping Hot Cooler")   
    tasmota.set_power(hot_relay, false)    
end

def peltier_is_on()
    print("Rule: Peltier is On. Starting Hot Cooler Now and Starting Cold Cooler in 30s")   
    tasmota.set_power(hot_relay, true)
    if hot_cooler_timer != nil 
        hot_cooler_timer.clear()
    end
    cold_cooler_timer = resetable_timer(10000, start_cold_cooler)
    #tasmota.set_timer(10000, def () start_cold_cooler() end)    
end

def peltier_is_off()
    #print("Rule: Peltier is off.")
    print("Rule: Peltier is off. Stopping hot cooler in 30s")  
    hot_cooler_timer = resetable_timer(30000, stop_hot_cooler)
    #tasmota.set_timer(10000, def () stop_hot_cooler() end)
end

def hot_cooler_is_off()
    print("Rule: Hot Cooler is Off")  
    if(tasmota.get_power(0)) #never let the peltier run without cooling at the hot side
        print("Rule: Start Hot Cooler Again (Peltier is On)") 
        tasmota.set_power(hot_relay, true)    
    end    
end

tasmota.add_rule("power1#State==0", peltier_is_off)
tasmota.add_rule("power1#State==1", peltier_is_on)
tasmota.add_rule("power3#State==0", hot_cooler_is_off)


class PID_driver
    #- display sensor value in the web UI -#    
    var N    
    var peltier_relay #relay number for the peltier    
    var Kp
    var Ki
    var Kd
    var Ts #sampling period (s)        
    var Sp    
    var uki_1
    var ukd_1
    var ek_1
    var sat     
    var uk
    
    var temp_1
    var temp_avg
    var temp_int_oCs
    var temp_interval_start_ms    
        
    var Dc_1
    var Dc_avg
    var Dc_int_percents
    var Dc_interval_start_ms

    def init()        
        self.N = 5
        self.peltier_relay=0 #relay number for the peltier    
        self.Kp=0.8
        self.Ki=0.0015
        self.Kd=0
        self.Ts=120.0 #sampling period (s)    
        self.N=1
        self.Sp = 18      
        self.uki_1 = 0
        self.ukd_1 = 0
        self.ek_1 = 0
        self.sat = 1 
        self.uk = 0

        self.temp_int_oCs = 0
        self.temp_interval_start_ms = 0        
        self.temp_avg = 0
        self.temp_1 = 0
    
        self.Dc_int_percents = 0
        self.Dc_interval_start_ms = 0        
        self.Dc_avg = 0        
        self.Dc_1 = 0

        self.calculate_temp_avg()
        self.calculate_dc_avg()

        print("Init: Starting PID loop")
        self.pid_loop() 
    end


    def pid_loop()
        var integration
        var s
        var temp
        var ek        
        var ukp
        var uki
        var ukd        
    
        s = json.load(tasmota.read_sensors())
        temp = s['DS18B20']['Temperature']
        self.calculate_temp_avg()
        self.calculate_dc_avg()  
        
        
        #ek = self.Sp - self.temp_avg #use the last loop average
        ek = self.Sp - temp #use the current temperature (easier for PID)
        ukp = self.Kp * ek #Eq (8)
        
        
        integration = (((self.Ki * self.Ts) / 2) * (ek + self.ek_1)) 
        uki = self.uki_1
        if(self.sat == 0)
            uki = uki + integration
        else
            if (((integration>0) && (self.uki_1 < 0)) || ((integration<0) && (self.uki_1 > 0)))
                uki = uki + integration
            end
        end
        ukd = self.Kd * self.N * (ek - self.ek_1) + (1 - self.N * self.Ts) * self.ukd_1 #Eq. (29)        
        self.uk = ukp + uki + ukd #Eq. (30)
        
        #save uk as u[k-1] for the next cycle
        self.uki_1 = uki;
        self.ukd_1 = ukd;
        self.ek_1 = ek;
        
        #never allow power greater than 100% or lower than 0%
        if((self.uk > 0)||(self.uk < -1.0))
            self.sat = 1
        else
            self.sat = 0
        end
        
        if (self.uk > 0)        
            self.uk = 0  
        end
        
        if (self.uk < -1.0)        
            self.uk = -0.999       
        end
    
        print("PID Loop: t:", temp ," last loop avg t: ",self.temp_avg, "ek: ", ek,", uk: ", self.uk, ", ukp:", ukp, ", uki: ", uki, ", ukd: ", ukd )
    
    
        if(self.uk < 0)  
            print("PID Loop: Peltier is programmed for ",-1*self.uk*self.Ts, " seconds")      
            tasmota.set_power(self.peltier_relay, true)
            tasmota.set_timer(int(-1000*self.uk*self.Ts), def () self.pid_end() end)        
        else
            tasmota.set_power(self.peltier_relay, false)
            print("PID Loop: Peltier will be kept turned off")    
        end       
        tasmota.set_timer(int(self.Ts*1000), def() self.pid_loop() end)
        
    end

    def pid_end()
        print("PID End: Peltier is off")
        tasmota.set_power(self.peltier_relay, false)        
    end


    def every_second()
        var s
        var temp
        var Dc
        var Ts = 1.0 #sampling time is 1s

        s = json.load(tasmota.read_sensors())
        temp = s['DS18B20']['Temperature']

        #integrate the temperature every second
        self.temp_int_oCs = ((Ts / 2) * (temp + self.temp_1)) + self.temp_int_oCs
        self.temp_1 = temp

        Dc = self.uk*-100.0
        #integrate the controller output every second
        self.Dc_int_percents = ((Ts / 2) * (Dc + self.Dc_1)) + self.Dc_int_percents
        self.Dc_1 = Dc
    end

    def calculate_temp_avg()
        var now = tasmota.millis()        
        var s
        if self.temp_interval_start_ms > 0
            self.temp_avg = self.temp_int_oCs / ((now - self.temp_interval_start_ms)/1000.0)            
        else
            s = json.load(tasmota.read_sensors())
            self.temp_1 = s['DS18B20']['Temperature']
            self.temp_avg = self.temp_1
        end
        self.temp_interval_start_ms = now
        self.temp_int_oCs = 0
    end

    def calculate_dc_avg()
        var now = tasmota.millis()                
        if self.Dc_interval_start_ms > 0
            self.Dc_avg = self.Dc_int_percents / ((now - self.Dc_interval_start_ms)/1000.0)            
        else            
            self.Dc_1 = self.uk*-100.0
            self.Dc_avg = self.Dc_1
        end
        self.Dc_interval_start_ms = now
        self.Dc_int_percents = 0        
    end

    def web_sensor()      
      import string      
      var msg = string.format(
               "{s}PID DutyCycle %.3f {e}"..
               "{s}PID Setpoint %.1f {e}",
                self.Dc_avg, self.Sp)
      tasmota.web_send_decimal(msg)
    end
  
    #- add sensor value to teleperiod -#
    def json_append()      
      import string          
      var msg = string.format(",\"PID\":{\"Sp\":%.3f,\"Dc\":%.3f,\"TempAvg\":%.3f,\"Kp\":%.3f,\"Ki\":%.3f,\"Kd\":%.3f,\"N\":%.3f,\"Ts\":%.3f}",
                self.Sp, self.Dc_avg, self.temp_avg,self.Kp,self.Ki,self.Kd,self.N,self.Ts)
      tasmota.response_append(msg)
    end
  
end

var pid = PID_driver()
tasmota.add_driver(pid)


mqtt.subscribe("cmnd/tasmota_43A028/TempSp", setpoint_change)

# ON system#boot DO backlog Var1 %mem1%; Var2 %mem2% ENDON
# ON DS18B20#Temperature>%Var1% DO power1 on ENDON
# ON DS18B20#Temperature<%Var2% DO backlog power1 off; power2 off ENDON
# ON power1#State==0 DO ruletimer1 30 ENDON
# ON power1#State==1 DO backlog ruletimer1 0; ruletimer2 30; power3 on ENDON
# ON rules#timer=1 do power3 off ENDON
# ON rules#timer=2 do power2 on ENDON