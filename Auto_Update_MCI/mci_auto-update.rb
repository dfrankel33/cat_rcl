name 'MCI Update - Utility CAT'
rs_ca_ver 20161221
short_description "MCI Update - Utility CAT"
import "sys_log"

parameter "param_mci_name" do
  label "MCI Name"
  type "string"
  description "json:{\"definition\":\"get_mci\"}"
end

parameter "param_ami_prefix" do
  label "AMI Prefix"
  type "string"
  min_length 4
  allowed_pattern "([A-Za-z0-9]{1,5})\-([A-Za-z0-9]{1,5})[^-]$"
end

parameter "param_frequency" do
  label "Scan Frequency"
  type "string"
  default "daily"
  allowed_values "hourly","daily","weekly","monthly"
end

parameter "param_first_scan_time" do
  label "First Scan Time"
  description "Value should be in hh:mm format in UTC time"
  type "string"
  min_length 5
  max_length 5
  default "23:59"
end

output "out_last_updated" do
  label "Last Updated"
  category "MCI"
end

output "out_mci_url" do
  label "MCI URL"
  category "MCI"
end

output "out_use_ami_id" do
  label "AMI ID"
  category "US-East-1 AMI"
end

output "out_use_ami_name" do
  label "AMI Name"
  category "US-East-1 AMI"
end

output "out_usw_ami_id" do
  label "AMI ID"
  category "US-West-1 AMI"
end

output "out_usw_ami_name" do
  label "AMI Name"
  category "US-West-1 AMI"
end

output "out_euc_ami_id" do
  label "AMI ID"
  category "EU-Central-1 AMI"
end

output "out_euc_ami_name" do
  label "AMI Name"
  category "EU-Central-1 AMI"
end

operation "launch" do
  definition "launch"
  output_mappings do {
    $out_last_updated => $last_updated,
    $out_mci_url => $mci_url,
    $out_use_ami_id => $use_ami_id,
    $out_use_ami_name => $use_ami_name,
    $out_usw_ami_id => $usw_ami_id,
    $out_usw_ami_name => $usw_ami_name,
    $out_euc_ami_id => $euc_ami_id,
    $out_euc_ami_name => $euc_ami_name
  } end
end

operation "scan_and_update" do
  definition "scan_and_update"
  output_mappings do {
    $out_last_updated => $last_updated,
    $out_use_ami_id => $use_ami_id,
    $out_use_ami_name => $use_ami_name,
    $out_usw_ami_id => $usw_ami_id,
    $out_usw_ami_name => $usw_ami_name,
    $out_euc_ami_id => $euc_ami_id,
    $out_euc_ami_name => $euc_ami_name
  } end
end

define launch($param_ami_prefix, $param_mci_name, $param_frequency, $param_first_scan_time) return $last_updated, $mci_url, $use_ami_id, $use_ami_name, $usw_ami_id, $usw_ami_name, $euc_ami_id, $euc_ami_name do
  task_label("Creating Scheduled Action")
  $recurrence = "FREQ="+upcase($param_frequency)
  $first_occurrence = strftime(now(), "%Y-%m-%d") + "T" + $param_first_scan_time + ":00+0000"
  @@scheduled_action = rs_ss.scheduled_actions.create(
    execution_id:     @@execution.id,
    name:             "scan_and_update",
    action:           "run",
    operation:        {
                        "name": "scan_and_update",
                        "configuration_options": [
                          {
                            "name": "param_ami_prefix",
                            "type": "string",
                            "value": $param_ami_prefix
                          },
                          {
                            "name": "param_mci_name",
                            "type": "string",
                            "value": $param_mci_name
                          }
                        ]
                      },
    recurrence:       $recurrence,
    first_occurrence: $first_occurrence
  )
  task_label("Setting Initial Output Values")
  $last_updated = "N/A"
  rs_cm.tags.multi_add(resource_hrefs: [@@deployment.href], tags: ["mci:last_updated="+$last_updated])

  @mci = rs_cm.multi_cloud_images.index(filter: ["name=="+$param_mci_name, "revision==0"])
  call find_account_number() retrieve $account_id
  call find_shard() retrieve $shard_number
  $mci_url = "https://us-"+$shard_number+".rightscale.com/acct/"+$account_id+"/multi_cloud_images/"+last(split(@mci.href,"/"))
  $use_cloud_href = "/api/clouds/1/"
  $usw_cloud_href = "/api/clouds/3/"
  $euc_cloud_href = "/api/clouds/9/"
  @images = @mci.settings().image()
  @use_image = rs_cm.images.empty()
  @usw_image = rs_cm.images.empty()
  @euc_image = rs_cm.images.empty()
  foreach @image in @images do
    $href = @image.href
    if $href =~ $use_cloud_href
      @use_image = @image
    elsif $href =~ $usw_cloud_href
      @usw_image = @image
    elsif $href =~ $euc_cloud_href
      @euc_image = @image
    else
      #skip
    end
  end
  $use_ami_id = @use_image.resource_uid
  $use_ami_name = @use_image.name
  $usw_ami_id = @usw_image.resource_uid
  $usw_ami_name = @usw_image.name
  $euc_ami_id = @euc_image.resource_uid
  $euc_ami_name = @euc_image.name

end

define scan_and_update($param_ami_prefix, $param_mci_name) return $last_updated, $use_ami_id, $use_ami_name, $usw_ami_id, $usw_ami_name, $euc_ami_id, $euc_ami_name do
  $mci_updated = "false"
  @mci = rs_cm.multi_cloud_images.index(filter: ["name=="+$param_mci_name, "revision==0"])
  call sys_log.summary("Scan and Update Report")
  call sys_log.detail("MCI OBJECT: "+to_s(to_object(@mci)))
  @settings = @mci.settings()
  call sys_log.detail("MCI SETTINGS OBJECT: "+to_s(to_object(@settings)))
  $use_cloud_href = "/api/clouds/1/"
  $usw_cloud_href = "/api/clouds/3/"
  $euc_cloud_href = "/api/clouds/9/"
  @mci_images = @mci.settings().image()
  call sys_log.detail("MCI IMAGES: "+to_s(to_object(@mci_images)))
  @use_image = rs_cm.images.empty()
  @usw_image = rs_cm.images.empty()
  @euc_image = rs_cm.images.empty()
  foreach @image in @mci_images do
    $href = @image.href
    if $href =~ $use_cloud_href
      @use_image = @image
      call sys_log.detail("USE IMAGE OBJECT: "+to_s(to_object(@use_image)))
    elsif $href =~ $usw_cloud_href
      @usw_image = @image
      call sys_log.detail("USW IMAGE OBJECT: "+to_s(to_object(@usw_image)))
    elsif $href =~ $euc_cloud_href
      @euc_image = @image
      call sys_log.detail("EUC IMAGE OBJECT: "+to_s(to_object(@euc_image)))
    else
      #skip
    end
  end
  $use_ami_id = @use_image.resource_uid
  $use_ami_name = @use_image.name
  call sys_log.detail("USE IMAGE UID: "+$use_ami_id)
  call sys_log.detail("USE IMAGE NAME: "+$use_ami_name)
  $usw_ami_id = @usw_image.resource_uid
  $usw_ami_name = @usw_image.name
  call sys_log.detail("USW IMAGE UID: "+$usw_ami_id)
  call sys_log.detail("USW IMAGE NAME: "+$usw_ami_name)
  $euc_ami_id = @euc_image.resource_uid
  $euc_ami_name = @euc_image.name
  call sys_log.detail("EUC IMAGE UID: "+$euc_ami_id)
  call sys_log.detail("EUC IMAGE NAME: "+$euc_ami_name)

  # US-East-1
  @use_cloud = rs_cm.get(href: "/api/clouds/1")
  @use_images = @use_cloud.images(filter: ["name=="+$param_ami_prefix, "visibility==private"])
  $use_image_names = @use_images.name[]
  call sys_log.detail("DISCOVERED USE IMAGE NAMES: "+to_s($use_image_names))
  $use_image_dates = []
  foreach $use_image_name in $use_image_names do
    $use_image_dates << split($use_image_name, "-")[2]
  end
  $use_last_image_date = last(sort($use_image_dates))
  call sys_log.detail("USE LAST IMAGE DATE : "+$use_last_image_date)
  $use_constructed_name = $param_ami_prefix + "-" + $use_last_image_date
  call sys_log.detail("USE CONSTRUCTED AMI NAME: "+$use_constructed_name)
  @use_image_search = @use_cloud.images(filter: ["name=="+$use_constructed_name, "visibility==private"])
  call sys_log.detail("DISCOVERED USE IMAGES WITH CONSTRUCTED NAME: "+to_s(to_object(@use_image_search)))
  if size(@use_image_search) > 1
    call sys_log.detail("WARNING: More than 1 image found matching that constructed name")
    $use_image_names = @use_image_search.name[]
    $use_time_stamps = []
    foreach $use_image_name in $use_image_names do
      if size(split($use_image_name, "-")) > 3
         $use_time_stamps << split($use_image_name, "-")[3]
      else
        # More than one image exists with the same date, but this one does not have a timestamp.
      end
    end
    $use_last_image_time_stamp = last(sort($use_time_stamps))
    call sys_log.detail("USE LAST TIME STAMP: "+$use_last_image_time_stamp)
    $use_constructed_name = $use_constructed_name + "-" + $use_last_image_time_stamp
    call sys_log.detail("USE UPDATED CONSTRUCTED NAME: "+$use_constructed_name)
    @target_use_image = @use_cloud.images(filter: ["name=="+$use_constructed_name, "visibility==private"])
    call sys_log.detail("USE TARGET AMI: "+to_s(to_object(@target_use_image)))
  else
    @target_use_image = @use_image_search
    call sys_log.detail("USE TARGET AMI: "+to_s(to_object(@target_use_image)))
  end

  if @target_use_image.name != $use_ami_name
    call sys_log.detail("Target Image Name does not match existing image name")
    call sys_log.detail("TARGET IMAGE NAME: "+@target_use_image.name)
    call sys_log.detail("OLD IMAGE NAME: "+$use_ami_name)

    #Update MCI
    @use_setting = rs_cm.multi_cloud_image_settings.empty()
    foreach @setting in @settings do
      if @setting.image().resource_uid == $use_ami_id
        @use_setting = @setting
        call sys_log.detail("USE MCI SETTING: "+to_s(to_object(@use_setting)))
      end
    end
    if size(@use_setting) == 1
      @use_setting.update(multi_cloud_image_setting: {image_href: @target_use_image.href})
    end
    $use_ami_id = @target_use_image.resource_uid
    $use_ami_name = @target_use_image.name
    call sys_log.detail("USE IMAGE UID: "+$use_ami_id)
    call sys_log.detail("USE IMAGE NAME: "+$use_ami_name)
    $mci_updated = "true"
  end

  # US-West-1
  @usw_cloud = rs_cm.get(href: "/api/clouds/3")
  @usw_images = @usw_cloud.images(filter: ["name=="+$param_ami_prefix, "visibility==private"])
  $usw_image_names = @usw_images.name[]
  call sys_log.detail("DISCOVERED USW IMAGE NAMES: "+to_s($usw_image_names))
  $usw_image_dates = []
  foreach $usw_image_name in $usw_image_names do
    $usw_image_dates << split($usw_image_name, "-")[2]
  end
  $usw_last_image_date = last(sort($usw_image_dates))
  call sys_log.detail("USW LAST IMAGE DATE : "+$usw_last_image_date)
  $usw_constructed_name = $param_ami_prefix + "-" + $usw_last_image_date
  call sys_log.detail("USW CONSTRUCTED AMI NAME: "+$usw_constructed_name)
  @usw_image_search = @usw_cloud.images(filter: ["name=="+$usw_constructed_name, "visibility==private"])
  call sys_log.detail("DISCOVERED USW IMAGES WITH CONSTRUCTED NAME: "+to_s(to_object(@usw_image_search)))
  if size(@usw_image_search) > 1
    call sys_log.detail("WARNING: More than 1 image found matching that constructed name")
    $usw_image_names = @usw_image_search.name[]
    $usw_time_stamps = []
    foreach $usw_image_name in $usw_image_names do
      if size(split($usw_image_name, "-")) > 3
         $usw_time_stamps << split($usw_image_name, "-")[3]
      else
        # More than one image exists with the same date, but this one does not have a timestamp.
      end
    end
    $usw_last_image_time_stamp = last(sort($usw_time_stamps))
    call sys_log.detail("USW LAST TIME STAMP: "+$usw_last_image_time_stamp)
    $usw_constructed_name = $usw_constructed_name + "-" + $usw_last_image_time_stamp
    call sys_log.detail("USW UPDATED CONSTRUCTED NAME: "+$usw_constructed_name)
    @target_usw_image = @usw_cloud.images(filter: ["name=="+$usw_constructed_name, "visibility==private"])
    call sys_log.detail("USW TARGET AMI: "+to_s(to_object(@target_usw_image)))
  else
    @target_usw_image = @usw_image_search
    call sys_log.detail("USW TARGET AMI: "+to_s(to_object(@target_usw_image)))
  end

  if @target_usw_image.name != $usw_ami_name
    call sys_log.detail("Target Image Name does not match existing image name")
    call sys_log.detail("TARGET IMAGE NAME: "+@target_usw_image.name)
    call sys_log.detail("OLD IMAGE NAME: "+$usw_ami_name)

    #Update MCI
    @usw_setting = rs_cm.multi_cloud_image_settings.empty()
    foreach @setting in @settings do
      if @setting.image().resource_uid == $usw_ami_id
        @usw_setting = @setting
        call sys_log.detail("USW MCI SETTING: "+to_s(to_object(@usw_setting)))
      end
    end
    if size(@usw_setting) == 1
      @usw_setting.update(multi_cloud_image_setting: {image_href: @target_usw_image.href})
    end
    $usw_ami_id = @target_usw_image.resource_uid
    $usw_ami_name = @target_usw_image.name
    call sys_log.detail("USW IMAGE UID: "+$usw_ami_id)
    call sys_log.detail("USW IMAGE NAME: "+$usw_ami_name)
    $mci_updated = "true"
  end

  # EU-Central-1
  @euc_cloud = rs_cm.get(href: "/api/clouds/9")
  @euc_images = @euc_cloud.images(filter: ["name=="+$param_ami_prefix, "visibility==private"])
  $euc_image_names = @euc_images.name[]
  call sys_log.detail("DISCOVERED EUC IMAGE NAMES: "+to_s($euc_image_names))
  $euc_image_dates = []
  foreach $euc_image_name in $euc_image_names do
    $euc_image_dates << split($euc_image_name, "-")[2]
  end
  $euc_last_image_date = last(sort($euc_image_dates))
  call sys_log.detail("EUC LAST IMAGE DATE : "+$euc_last_image_date)
  $euc_constructed_name = $param_ami_prefix + "-" + $euc_last_image_date
  call sys_log.detail("EUC CONSTRUCTED AMI NAME: "+$euc_constructed_name)
  @euc_image_search = @euc_cloud.images(filter: ["name=="+$euc_constructed_name, "visibility==private"])
  call sys_log.detail("DISCOVERED EUC IMAGES WITH CONSTRUCTED NAME: "+to_s(to_object(@euc_image_search)))
  if size(@euc_image_search) > 1
    call sys_log.detail("WARNING: More than 1 image found matching that constructed name")
    $euc_image_names = @euc_image_search.name[]
    $euc_time_stamps = []
    foreach $euc_image_name in $euc_image_names do
      if size(split($euc_image_name, "-")) > 3
         $euc_time_stamps << split($euc_image_name, "-")[3]
      else
        # More than one image exists with the same date, but this one does not have a timestamp.
      end
    end
    $euc_last_image_time_stamp = last(sort($euc_time_stamps))
    call sys_log.detail("EUC LAST TIME STAMP: "+$euc_last_image_time_stamp)
    $euc_constructed_name = $euc_constructed_name + "-" + $euc_last_image_time_stamp
    call sys_log.detail("EUC UPDATED CONSTRUCTED NAME: "+$euc_constructed_name)
    @target_euc_image = @euc_cloud.images(filter: ["name=="+$euc_constructed_name, "visibility==private"])
    call sys_log.detail("EUC TARGET AMI: "+to_s(to_object(@target_euc_image)))
  else
    @target_euc_image = @euc_image_search
    call sys_log.detail("EUC TARGET AMI: "+to_s(to_object(@target_euc_image)))
  end

  if @target_euc_image.name != $euc_ami_name
    call sys_log.detail("Target Image Name does not match existing image name")
    call sys_log.detail("TARGET IMAGE NAME: "+@target_euc_image.name)
    call sys_log.detail("OLD IMAGE NAME: "+$euc_ami_name)

    #Update MCI
    @euc_setting = rs_cm.multi_cloud_image_settings.empty()
    foreach @setting in @settings do
      if @setting.image().resource_uid == $euc_ami_id
        @euc_setting = @setting
        call sys_log.detail("EUC MCI SETTING: "+to_s(to_object(@euc_setting)))
      end
    end
    if size(@euc_setting) == 1
      @euc_setting.update(multi_cloud_image_setting: {image_href: @target_euc_image.href})
    end
    $euc_ami_id = @target_euc_image.resource_uid
    $euc_ami_name = @target_euc_image.name
    call sys_log.detail("EUC IMAGE UID: "+$euc_ami_id)
    call sys_log.detail("EUC IMAGE NAME: "+$euc_ami_name)
    $mci_updated = "true"
  end

  if $mci_updated == "true"
    $last_updated = strftime(now(), "%Y-%m-%d %H:%M")
    rs_cm.tags.multi_add(resource_hrefs: [@@deployment.href], tags: ["mci:last_updated="+$last_updated])
  else
    $last_updated = tag_value(@@deployment, "mci:last_updated")
  end

end



define find_account_number() return $account_id do
  $session = rs_cm.sessions.index(view: "whoami")
  $account_id = last(split(select($session[0]["links"], {"rel":"account"})[0]["href"],"/"))
end

define find_shard() return $shard_number do
  call find_account_number() retrieve $account_number
  $account = rs_cm.get(href: "/api/accounts/" + $account_number)
  $shard_number = last(split(select($account[0]["links"], {"rel":"cluster"})[0]["href"],"/"))
end

define get_mci() return $names do
  @mcis = rs_cm.multi_cloud_images.index(filter: ["revision==0"])
  $names = @mcis.name[]
end