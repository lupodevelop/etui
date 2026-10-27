import gleam/list
import gleeunit/should
import unicode_rows

pub fn mixed_rows_preserve_cells_styles_links_and_clip_to_their_row_test() {
  list.each(unicode_rows.outcomes(), fn(outcome) {
    #(outcome.id, outcome.actual)
    |> should.equal(#(outcome.id, outcome.expected))
  })
}
