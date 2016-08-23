require 'pry'
require 'scraperwiki'
require "capybara/poltergeist"
require 'open-uri'
require 'ocd_lookup'
require 'scraped_page_archive/capybara'

Capybara.default_selector = :xpath

def scrape(url)
  # Using poltergeist because the list page uses session variables
  browser =  Capybara::Session.new(:poltergeist)
  people = scrape_list(url,browser)
  # we completely walk the list DOM then go to the individual mp pages so we can use the same Capybara session
  people.each do  |basic_details|
    more_details =  scrape_person(basic_details[:source], browser)
    ScraperWiki.save_sqlite([:id], basic_details.merge(more_details))
  end

end

def ocd_lookup
  @ocd_lookup ||= begin
    ocd_csv_url = 'https://github.com/theyworkforyou/uganda_ocd_ids/raw/master/identifiers/country-ug.csv'
    OcdLookup::DivisionId.parse(open(ocd_csv_url).read)
  end
end

def scrape_list(url,browser)
  %w[a e i o u].map do |vowel|
    browser.visit(url)
    browser.click_link 'Search Other Parliaments'
    browser.find("//input[contains(@name, '.sKey')]").set(vowel) # Search box
    browser.find("//select[contains(@name, '.pal')]").select('Only The 9th Parliament') # Term dropdown
    browser.find('//input[@value="Search Now"]').click
    browser.click_button 'Show all at once' if browser.has_button?('Show all at once')
    browser.find_all('//body/table/tbody/tr[position()>2 and position()<last()]').map  do |row|
      scrape_table_row(url, row)
    end
  end.flatten.uniq { |person| person[:id] }
end

def scrape_table_row(url, row)
  year = '2015'
  absolute_uri = URI.join(url, row.find('./td/a')[:href]).to_s
  person = {}
  names = row.find('./td[position()=1]').text.strip.split(/[[:space:]]/, 2).reverse
  person[:name] = names.join(" ")
  person[:given_name] = names.first
  person[:family_name] = names.last
  person[:sort_name] = "#{names.last}, #{names.first}"

  person[:id] = year + '-'+/&j=(?<id>\d*)&const/.match(absolute_uri)[:id].to_s
  person[:source] = absolute_uri
  person[:url] = absolute_uri
  person[:district] = row.find('./td[position()=4]').text.strip
  person[:constituency] = row.find('./td[position()=3]').text.strip

  special = ["PWD", "YOUTH", "EX-OFFICIO", "Workers' Represantive", "Woman Representative", "UPDF", "Workers' Representative"].to_set
  if special.include? person[:constituency]
    spelling_fixups = {
      "Workers' Represantive" => "Workers' Representative",
    }
    person[:legislative_membership_type] = spelling_fixups.fetch(person[:constituency], person[:constituency])
    person[:constituency] = ""

    person[:area_id] = ocd_lookup.find(district: person[:district].gsub(/district/i, '').strip)
  else
    person[:area_id] = ocd_lookup.find(district: person[:district].gsub(/district/i, '').strip, constituency: person[:constituency])
  end

  warn "Couldn't find :area_id for district=#{person[:district]} constituency=#{person[:constituency]}" if person[:area_id].nil?

  person
end

def party_info(str)
  party_info = /(.*)[[:space:]]*\((.*?)\)/.match(str)
  binding.pry unless party_info
  return party_info[1].strip, party_info[2].strip
end


def scrape_person (url, browser)
  person = {}
  browser.visit(url)
  browser.within('//*/table/tbody') do
    person = {
        :image =>          URI.join(url, browser.find('./tr[position()=1]/td/img')[:src]).to_s,
        :gender =>         browser.find(with_label 'Gender:').text.strip.downcase,
        :martial_status => browser.find(with_label 'Marital Status:').text.strip.downcase,
        :email =>          browser.find(with_label 'Email address:').text.strip,
        :address =>        browser.find(with_label 'Postal Address:').text.strip,
        :phone =>          browser.find(with_label 'Mobile Telephone:').text.strip,
        :religion =>       browser.find(with_label 'Religion:').text.strip,
    }

    party_selector = with_label 'Political Party:'
    if browser.has_selector? party_selector
      person[:party_id], person[:party] = party_info(browser.find(party_selector).text.strip)
    end

    raw_dob = browser.find(with_label 'Date of birth:').text.strip
    person[:date_of_birth] = Date.strptime(   raw_dob, '%d/%m/%Y' ).strftime("%Y-%m-%d") unless raw_dob.empty?
  end
  return person
end

def with_label(label)
  return "./tr/td[contains(./b/text(),'#{label}')]/following-sibling::td"
end

scrape('http://www.parliament.go.ug/mpdata/mps.hei')
