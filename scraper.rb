require 'scraperwiki'
require "capybara/poltergeist"

Capybara.default_selector = :xpath

def scrape(url)
  # Using poltergeist because the list page uses session variables
  browser =  Capybara::Session.new(:poltergeist)
  people = scrape_list(url,browser)
  # we completely walk the list DOM then go to the individual mp pages so we can use the same Capybara session
  people.each do  |basic_details|
    more_details =  scrape_person(basic_details[:url], browser)
    ScraperWiki.save_sqlite(['id'], basic_details.merge(more_details))
  end

end

def scrape_list(url,browser)
  year = '2015'
  people = []
  browser.visit(url)
  browser.click_button 'Show all at once'
  browser.within( '//body/table') do
    browser.all('./tbody/tr[position()>2 and position()<last()]').each  do |row|
      absolute_uri = URI.join(url, row.find('./td/a')[:href]).to_s
      person = {}
      person['id'] = year + '-'+/&j=(?<id>\d*)&const/.match(absolute_uri)[:id].to_s
      person[:url] = absolute_uri
      person[:name] = row.find('./td[position()=1]').text.strip
      person[:area] = row.find('./td[position()=4]').text.strip
      people.push(person)
    end
  end
  return people
end

def scrape_person (url,browser)
  person = {}
  browser.visit(url)
  browser.within( '//*/table/tbody') do
      person = {
          :image => URI.join(url, browser.find('./tr[position()=1]/td/img')[:src]).to_s ,
          :gender =>         browser.find(with_label 'Gender:').text.strip,
          :martial_status => browser.find(with_label 'Marital Status:').text.strip,
          :email =>          browser.find(with_label 'Email address:').text.strip,
          :postal_address => browser.find(with_label 'Postal Address:').text.strip,
          :phone =>          browser.find(with_label 'Mobile Telephone:').text.strip,
          :religion =>       browser.find(with_label 'Religion:').text.strip,
          :date_of_birth =>  browser.find(with_label 'Date of birth:').text.strip,
      }
  end
  return person
end

def with_label(label)
  return "./tr/td[contains(./b/text(),'#{label}')]/following-sibling::td"
end

scrape('http://www.parliament.go.ug/mpdata/mps.hei')
