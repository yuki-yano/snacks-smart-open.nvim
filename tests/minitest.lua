local files = vim.fn.globpath("tests", "*_test.lua", false, true)
table.sort(files)

MiniTest.run({
  collect = {
    emulate_busted = false,
    find_files = function()
      return files
    end,
  },
})
