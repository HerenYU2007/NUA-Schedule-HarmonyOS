import java.io.File;
import jxl.Workbook;
import jxl.Sheet;
public class CheckExport {
  public static void main(String[] args) throws Exception {
    Workbook book = Workbook.getWorkbook(new File(args[0]));
    try { Sheet sheet=book.getSheet(0); if(sheet.getColumns()!=11 || !sheet.getCell(0,0).getContents().equals("课程名称") || !sheet.getCell(7,1).getContents().equals("文313") || !sheet.getCell(9,1).getContents().equals("2")) throw new AssertionError("XLS layout/Unicode/metadata mismatch"); System.out.println("Independent JExcelAPI XLS validation passed: 11 columns, Unicode, room and credits."); } finally {book.close();}
  }
}
