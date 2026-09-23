# frozen_string_literal: true

module ::DiscourseCategoryLatestTopics
  module PageStyleExtension
    def values
      super + [{ name: "category_page_style.categories_with_latest_topics", value: PAGE_STYLE }]
    end
  end
end
