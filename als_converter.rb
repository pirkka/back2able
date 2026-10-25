require 'rexml/document'

module AlsConverter
  TARGET_ATTRIBUTES = {
    'MajorVersion' => '5',
    'MinorVersion' => '11.0_11300',
    'SchemaChangeCount' => '7',
    'Creator' => 'Ableton Live 11.3.40b2',
    'Revision' => '97b2aa4f9e88ecec40a7dc6f0e9c707631d5a5c7'
  }.freeze

  SCALE_NAMES = {
    '0' => 'Major'
  }.freeze

  REMOVED_ELEMENTS = %w[
    MidiEditorLaneModel
    ArrangementClipsListWrapper
    TakeLanesListWrapper
    AutomationEnvelopesListWrapper
    NoteAlgorithms
    TuningSystems
    ControllerLayoutCustomization
    MpePitchBendUsesTuning
    IsTuned
    SourceHint
    SamplesToAutoWarp
    LocalFiltersJson
    KeepRecordMonitoringLatency
    ReWireDeviceMidiTargetId
    DefaultGrooveId
    GroovesListWrapper
    BreakoutIsExpanded
  ].freeze

  REMOVED_ATTRIBUTES = %w[
    SelectedToolPanel
    SelectedTransformationName
    SelectedGeneratorName
  ].freeze

  LANE_LAYOUT = {
    'ContentLanes' => [
      ['4', '41', 'false'],
      ['5', '25', 'true']
    ],
    'ExpressionLanes' => [
      ['0', '41', 'false'],
      ['1', '41', 'false'],
      ['2', '41', 'true'],
      ['3', '41', 'true']
    ]
  }.freeze

  def self.convert(xml_content, full: true)
    document = REXML::Document.new(xml_content)
    attribute_names = []
    document.root.attributes.each_attribute { |attribute| attribute_names << attribute.expanded_name }
    attribute_names.each { |name| document.root.attributes.delete(name) }
    TARGET_ATTRIBUTES.each { |name, value| document.root.attributes[name] = value }

    apply_live_11_transformations(document) if full

    document.to_s
  end

  def self.apply_live_11_transformations(document)
    lane_parents = {}
    tracks = []
    clip_slots = []
    container_tracks = []
    to_remove = []

    each_element(document.root) do |element|
      if REMOVED_ELEMENTS.include?(element.name)
        to_remove << element
        next
      end

      if element.name == 'MidiControllerRange' && element.parent && element.parent.name == 'TimeSignature'
        to_remove << element
        next
      end

      if LANE_LAYOUT.key?(element.name)
        lane_parents[element.name] = element
        next
      end

      if element.parent && %w[Tracks LiveSet].include?(element.parent.name)
        container_tracks << element if %w[GroupTrack ReturnTrack MainTrack MasterTrack].include?(element.name)
      end

      if %w[AudioTrack MidiTrack].include?(element.name) && element.parent && element.parent.name == 'Tracks'
        tracks << element
      end

      clip_slots << element if element.name == 'ClipSlot' && element.parent && element.parent.name == 'ClipSlotList'

      rename_element(element)
      convert_scale_information(element)
      convert_values(element)
      convert_oversampling(element)
      remove_live_12_attributes(element)
    end

    to_remove.each do |element|
      element.parent.delete_element(element) if element.parent
    end

    lane_parents.each { |name, element| replace_lanes(element, name) }
    tracks.each { |track| add_missing_track_fields(track) }
    container_tracks.each { |track| clear_clip_slots(track) }
    clip_slots.each { |clip_slot| add_need_refreeze(clip_slot) }
  end

  def self.each_element(element, &block)
    stack = [element]
    until stack.empty?
      current = stack.pop
      block.call(current)
      stack.concat(current.elements.to_a)
    end
  end

  def self.rename_element(element)
    case element.name
    when 'MainTrack'
      element.name = 'MasterTrack'
      rename_master_track_names(element)
    when 'AutoColorPickerForReturnAndMainTracks'
      element.name = 'AutoColorPickerForReturnAndMasterTracks'
    when 'IsSongTempoLeader'
      element.name = 'IsSongTempoMaster'
    end
  end

  def self.rename_master_track_names(master_track)
    {
      'EffectiveName' => { 'Main' => 'Master' },
      'MemorizedFirstClipName' => { '0-Main' => '0-Master' }
    }.each do |element_name, values|
      element = master_track.elements["Name/#{element_name}"]
      next unless element

      value = element.attributes['Value']
      element.attributes['Value'] = values[value] if values.key?(value)
    end
  end

  def self.convert_scale_information(element)
    return unless element.name == 'ScaleInformation'

    root = element.elements['Root']
    root.name = 'RootNote' if root

    name = element.elements['Name']
    return unless name

    value = name.attributes['Value']
    return unless value && value.match?(/\A\d+\z/)

    name.attributes['Value'] = SCALE_NAMES.fetch(value, 'Major')
  end

  def self.convert_values(element)
    value = element.attributes['Value']
    return unless value

    case element.name
    when 'Target'
      element.attributes['Value'] = 'AudioOut/Master' if value == 'AudioOut/Main'
      element.attributes['Value'] = 'AudioIn/Master' if value == 'AudioIn/Main'
    when 'UpperDisplayString'
      element.attributes['Value'] = 'Master' if value == 'Main'
    end
  end

  def self.convert_oversampling(element)
    return unless element.name == 'Oversampling' && element.parent && element.parent.name == 'Saturator'

    value = element.attributes['Value']
    element.attributes['Value'] = '1' if value == 'true'
    element.attributes['Value'] = '0' if value == 'false'
  end

  def self.remove_live_12_attributes(element)
    REMOVED_ATTRIBUTES.each { |name| element.attributes.delete(name) }
  end

  def self.replace_lanes(element, name)
    element.elements.to_a.each { |child| element.delete_element(child) }

    LANE_LAYOUT[name].each_with_index do |(type, size, minimized), id|
      lane = element.add_element('ExpressionLane', 'Id' => id.to_s)
      lane.add_element(value_element('Type', type))
      lane.add_element(value_element('Size', size))
      lane.add_element(value_element('IsMinimized', minimized))
    end
  end

  def self.add_missing_track_fields(track)
    insert_before_or_append(track, 'PostProcessFreezeClips', value_element('VelocityDetail', '0'))
    insert_before_or_append(track, 'PostProcessFreezeClips', bool_element('NeedArrangerRefreeze', 'true'))

    return unless track.name == 'MidiTrack'

    track.add_element(value_element('ReWireSlaveMidiTargetId', '0')) unless track.elements['ReWireSlaveMidiTargetId']
    track.add_element(value_element('PitchbendRange', '96')) unless track.elements['PitchbendRange']
  end

  def self.add_need_refreeze(clip_slot)
    return if clip_slot.elements['NeedRefreeze']

    anchor = clip_slot.elements['HasStop']
    need_refreeze = bool_element('NeedRefreeze', 'true')
    if anchor
      clip_slot.insert_after(anchor, need_refreeze)
    else
      clip_slot.add_element(need_refreeze)
    end
  end

  def self.clear_clip_slots(track)
    each_element(track) do |element|
      next unless element.name == 'ClipSlotList'

      element.elements.to_a.each { |child| element.delete_element(child) }
    end
  end

  def self.insert_before_or_append(parent, anchor_name, element)
    anchor = parent.elements[anchor_name]
    if anchor
      parent.insert_before(anchor, element)
    else
      parent.add_element(element)
    end
  end

  def self.value_element(name, value)
    element = REXML::Element.new(name)
    element.add_attribute('Value', value)
    element
  end

  def self.bool_element(name, value)
    value_element(name, value)
  end
end
