
// installDlg.h : header file
//

#pragma once
#include "afxwin.h"

void setDeviceInfo();

// CinstallDlg dialog
class CinstallDlg : public CDialogEx
{
// Construction
public:
	CinstallDlg(CWnd* pParent = NULL);	// standard constructor

	// Dialog Data
	enum { IDD = IDD_INSTALL_DIALOG };

	protected:
	virtual void DoDataExchange(CDataExchange* pDX);	// DDX/DDV support


// Implementation
protected:
	HICON m_hIcon;

	// Generated message map functions
	virtual BOOL OnInitDialog();
	afx_msg void OnSysCommand(UINT nID, LPARAM lParam);
	afx_msg void OnPaint();
	afx_msg HCURSOR OnQueryDragIcon();
	DECLARE_MESSAGE_MAP()

public:
	CStatic mInfoStatic;
	CStatic mMessage;
	CStatic mDeviceImage;
	CBitmap mDeviceBitmapGrayed;
	CBitmap mDeviceBitmapClear;

	void setDeviceImage(int idc);
	void setMessage(char *msg);
	void setInfo(char *msg);
	afx_msg void OnBnClickedCancel();
	afx_msg void OnBnClickedOk();
	char* CinstallDlg::askForCoreDirectory();
	char * CinstallDlg::getIosPath();
};
