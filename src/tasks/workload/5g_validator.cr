# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "Test if a 5G core has SMF/UPF heartbeat"
task "smf_upf_heartbeat" do |t, args|
  CNFManager::Task.task_runner(args) do |args, config|
    task_start_time = Time.utc
    testsuite_task = "suci_enabled"
    Log.for(testsuite_task).info { "Starting test" }

    Log.debug { "cnf_config: #{config}" }
    suci_found : Bool | Nil
    smf = config.cnf_config[:smf_label]? 
    upf = config.cnf_config[:upf_label]? 
    Log.info { "smf: #{smf}" }
    Log.info { "upf: #{upf}" }
    smf_key : String  = ""
    smf_value : String = ""
    smf_key = config.cnf_config[:smf_label].split("=").first if smf
    smf_value = config.cnf_config[:smf_label].split("=").last if upf

    if smf && upf 

      command = "-ni any -Y 'pfcp.msg_type == 1 or pfcp.msg_type == 2' -T json"

      #Baseline 
      tshark_log_name = K8sTshark.log_of_tshark_by_label(command, smf_key, smf_value, duration="120")
      if tshark_log_name && 
          !tshark_log_name.empty? && 
          (tshark_log_name =~ /not found/) == nil
        scan = K8sTshark.regex_tshark_log_scan(/"pfcp\.msg_type": "(1|2)"/, tshark_log_name) 
        if scan
          baseline_count = scan.size
          Log.info { "Baseline matches: #{baseline_count}" }
        end
      end

      #Chaos Matches
      sync_channel = Channel(Nil).new
      spawn do
        Log.info { "before invoke of pod delete" }
        args.named["pod_labels"]="#{smf},#{upf}"
        t.invoke("pod_delete", args)
        Log.info { "after invoke of pod delete" }
        sync_channel.send(nil)
      end
      Log.info { "Main pod delete thread continuing" }


      tshark_log_name = K8sTshark.log_of_tshark_by_label(command, smf_key, smf_value, duration="120")
      if tshark_log_name && 
          !tshark_log_name.empty? && 
          (tshark_log_name =~ /not found/) == nil

        Log.info { "TShark Log File: #{tshark_log_name}" }
        scan = K8sTshark.regex_tshark_log_scan(/"pfcp\.msg_type": "(1|2)"/, tshark_log_name) 
        if scan
          chaos_count = scan.size
          Log.info { "Chaos Matches: #{chaos_count}" }
        end
      end

      Log.info { "before pod delete receive" }
      sync_channel.receive
      Log.info { "after pod delete receive" }

      Log.info { "Chaos Matches: #{chaos_count}" }
      Log.info { "Baseline matches: #{baseline_count}" }

      if chaos_count && baseline_count
        difference = (chaos_count.to_i - baseline_count.to_i).abs
        if difference <= 5
          Log.info { "The integers are within a value of 5. Passing" }
          heartbeat_found = true
        else
          Log.info { "The integers are not within a value of 5. Failing" }
          heartbeat_found = false
        end
      else
          Log.info { "Heartbeat not found" }
          heartbeat_found = false
      end

    else
      heartbeat_found = false
      puts "no 5g labels".colorize(:red)
    end

    if heartbeat_found 
      resp = upsert_passed_task(testsuite_task,"✔️  PASSED: Core uses SUCI 5g authentication", task_start_time)
    else
      resp = upsert_failed_task(testsuite_task, "✖️  FAILED: Core does not use SUCI 5g authentication", task_start_time)
    end
    resp
  ensure
    Helm.delete("ueransim")
    ClusterTools.uninstall
    ClusterTools.install
  end
end
