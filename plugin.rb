# frozen_string_literal: true

# name: discourse-category-latest-topics
# about: TODO
# meta_topic_id: TODO
# version: 0.0.1
# authors: Discourse
# url: TODO
# required_version: 2.7.0

enabled_site_setting :discourse_category_latest_topics_enabled

module ::DiscourseCategoryLatestTopics
  PLUGIN_NAME = "discourse-category-latest-topics"
end

require_relative "lib/discourse_category_latest_topics/engine"

after_initialize do
  # Code which should run after Rails has finished booting
end
