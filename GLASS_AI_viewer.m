classdef GLASS_AI_viewer < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                   matlab.ui.Figure
        GridLayout                 matlab.ui.container.GridLayout
        LeftPanel                  matlab.ui.container.Panel
        Image                      matlab.ui.control.Image
        OverlayOpacitySlider       matlab.ui.control.Slider
        OverlayOpacitySliderLabel  matlab.ui.control.Label
        LoadimagesButton           matlab.ui.control.Button
        SelectGLASSAIoutputButton  matlab.ui.control.Button
        ClassFileNameField         matlab.ui.control.EditField
        SelectImageButton          matlab.ui.control.Button
        ImageFileNameField         matlab.ui.control.EditField
        RightPanel                 matlab.ui.container.Panel
        Panel                      matlab.ui.container.Panel
    end

    % Properties that correspond to apps with auto-reflow
    properties (Access = private)
        onePanelWidth = 576;
    end

    
    properties (Access = private)
        SELECTED_DIR_PATH % Last folder a file was chosen from; starts at user's desktop
        IMAGE_DIR_PATH
        IMAGE_FILE_NAME
        CLASS_DIR_PATH
        CLASS_FILE_NAME
        IMAGE_VIEWER % viewer object to show images in app panel
    end
    
    methods (Access = private)
    
      
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            % start file search at the user's desktop
            app.SELECTED_DIR_PATH = fullfile(char(java.lang.System.getProperty('user.home')), 'Desktop');
            % initialize image viewing panel
            app.IMAGE_VIEWER = viewer2d(Parent = app.Panel);
        end

        % Button pushed function: SelectImageButton
        function SelectImageButtonPushed(app, event)
            [image_file_name, image_dir_path] = uigetfile({'*.svs;*.qptiff;*.tiff;*.tif;*.png;*.jpg', 'Image files'}, ...
                "Select input image file", ...
                app.SELECTED_DIR_PATH);
            if isequal(image_file_name,0)
                app.IMAGE_DIR_PATH = '';
                app.IMAGE_FILE_NAME = '';
                app.ImageFileNameField.Value = '';
                return % no file selected
            else
                app.IMAGE_DIR_PATH = image_dir_path;
                app.IMAGE_FILE_NAME = image_file_name;
                app.SELECTED_DIR_PATH = image_dir_path;
                app.ImageFileNameField.Value = image_file_name;
            end
        end

        % Button pushed function: SelectGLASSAIoutputButton
        function SelectGLASSAIoutputButtonPushed(app, event)
            [class_file_name, class_dir_path] = uigetfile('*.mat', ...
                "Select matching GLASS-AI classes.mat file", ...
                app.SELECTED_DIR_PATH);
            if isequal(class_file_name,0)
                app.CLASS_DIR_PATH = '';
                app.CLASS_FILE_NAME = '';
                app.ClassFileNameField.Value = '';
                return % no file selected
            else
                app.CLASS_DIR_PATH = class_dir_path;
                app.CLASS_FILE_NAME = class_file_name;
                app.SELECTED_DIR_PATH = class_dir_path;
                app.ClassFileNameField.Value = class_file_name;
            end
        end

        % Button pushed function: LoadimagesButton
        function LoadimagesButtonPushed(app, event)
            % clear existing viewer
            clear(app.IMAGE_VIEWER)
            app.Panel.Title = "Image Viewer";
            try
                % read in GLASS-AI class file
                class_file_loaded = false;
                if not(isempty(app.CLASS_FILE_NAME))
                    grade_map = load(fullfile(app.CLASS_DIR_PATH,app.CLASS_FILE_NAME));

                    % verify loaded MAT file contains 'classifications'
                    if ~isstruct(grade_map) || ~isfield(grade_map, 'classifications')
                        errordlg("The selected .mat file does not contain the expected 'classifications' variable.");
                        return
                    end
                    grade_map = grade_map.classifications;
                    grade_map = blockedImage(grade_map);

                    cmap = colormap( [0 0 0; ... % Background
                        0 1 0; ... % Grade 1
                        0 0 1; ... % Grade 2
                        1 1 0; ... % Grade 3
                        1 0 0; ... % Grade 4
                        0 1 1; ... % Alveoli
                        1 0 1; ... % Airway
                        1 1 1; ... % Skipped (or manually ignored)
                        0.5 0 0.5]); % Grade 5 (manually added)

                    class_file_loaded = true;
                end

                % read in image file
                image_file_loaded = false;
                if not(isempty(app.IMAGE_FILE_NAME))
                    [~, ~, image_file_ext] = fileparts(app.IMAGE_FILE_NAME);
                    switch image_file_ext
                        case {'.svs','.qptiff'}
                            %
                            input_image = blockedImage(fullfile(app.IMAGE_DIR_PATH, app.IMAGE_FILE_NAME));
                        otherwise
                            input_image = blockedImage(fullfile(app.IMAGE_DIR_PATH, app.IMAGE_FILE_NAME));
                    end
                    image_file_loaded = true;
                end

                % load images into viewer panel
                % both files loaded
                if all([class_file_loaded, image_file_loaded])
                    % verify that the selected image and classification file are the same size
                    if not(all(input_image.Size(1,1:2) == grade_map.Size))
                        errordlg({"The selected images are not the same size.", ...
                            "Make sure that you select the matching image and GLASS-AI classification .mat file."})
                        return
                    end

                    h = imageshow(input_image, ...
                        Parent = app.IMAGE_VIEWER,...
                        OverlayData = grade_map, ...
                        OverlayColorMap = cmap, ...
                        OverlayDisplayRangeMode = 'manual',...
                        OverlayDisplayRange = [0 8]);

                    % add image name to UIPanel title
                    app.Panel.Title = app.IMAGE_FILE_NAME;

                    % add scale bar using openslide metadata if available
                    if contains(image_file_ext,[".svs",".qptiff"])
                       
                        % determine microns per pixel
                        % add scale bar using slide image metadata if available
                        if image_file_ext == ".svs"
                            svsInfo =  imfinfo(fullfile(app.IMAGE_DIR_PATH, app.IMAGE_FILE_NAME));
                            image_mpp = extract(string(svsInfo(1).ImageDescription), regexpPattern('(?<=\|MPP = )([\d.]+)(?=\|)'));
                            image_mpp = str2double(image_mpp);
                        elseif image_file_ext  == ".qptiff"
                            qptiffInfo = imfinfo(fullfile(app.IMAGE_DIR_PATH, app.IMAGE_FILE_NAME));
                            image_mpp = extract(string(qptiffInfo(1).ImageDescription), regexpPattern('(?<=<PixelSizeMicrons>)([\d.]+)(?=</PixelSizeMicrons>)'));
                            image_mpp = str2double(image_mpp(1));
                        end

                        %make micron scale transformation for image
                        image_rc = input_image.Size(1,1:2);
                        rows = image_rc(1);
                        cols = image_rc(2);

                        % convert pixel limits to micron limits
                        % Limits span from 0.5 to (NumPixels + 0.5) * resolution
                        xLimits = [0.5, cols + 0.5] * image_mpp;
                        yLimits = [0.5, rows + 0.5] * image_mpp;
                        % create the spatial referencing object to apply in transform
                        R = imref2d(input_image.Size(1,1:2), xLimits, yLimits);
                        h.Transformation = R;
                        h.Parent.ScaleBar = "on";
                        h.Parent.ScaleBarStyle = "measure";
                        h.Parent.SpatialUnits = "microns";

                    end

                    % initialize overlay opacity
                    set(h, 'OverlayAlpha', app.OverlayOpacitySlider.Value);

                    % only image file loaded
                elseif image_file_loaded
                    h = imageshow(input_image, Parent = app.IMAGE_VIEWER);

                    % add image name to UIPanel title
                    app.Panel.Title = app.IMAGE_FILE_NAME;

                    % add scale bar using slide image metadata if available
                    if image_file_ext == ".svs"
                        svsInfo =  imfinfo(fullfile(app.IMAGE_DIR_PATH, app.IMAGE_FILE_NAME));
                        image_mpp = extract(string(svsInfo(1).ImageDescription), regexpPattern('(?<=\|MPP = )([\d.]+)(?=\|)'));
                        image_mpp = str2double(image_mpp);
                    elseif image_file_ext  == ".qptiff"
                        qptiffInfo = imfinfo(fullfile(app.IMAGE_DIR_PATH, app.IMAGE_FILE_NAME));
                        image_mpp = extract(string(qptiffInfo(1).ImageDescription), regexpPattern('(?<=<PixelSizeMicrons>)([\d.]+)(?=</PixelSizeMicrons>)'));
                        image_mpp = str2double(image_mpp(1));
                    end

                    %make micron scale transformation for image
                    image_rc = input_image.Size(1,1:2);
                    rows = image_rc(1);
                    cols = image_rc(2);

                    % convert pixel limits to micron limits
                    % Limits span from 0.5 to (NumPixels + 0.5) * resolution
                    xLimits = [0.5, cols + 0.5] * image_mpp;
                    yLimits = [0.5, rows + 0.5] * image_mpp;
                    % create the spatial referencing object to apply in transform
                    R = imref2d(input_image.Size(1,1:2), xLimits, yLimits);
                    h.Transformation = R;
                    h.Parent.ScaleBar = "on";
                    h.Parent.ScaleBarStyle = "measure";
                    h.Parent.SpatialUnits = "microns";

                    % only class file loaded
                elseif class_file_loaded
                    h = imageshow(grade_map, ...
                        Parent = app.IMAGE_VIEWER, ...
                        ColorMap = cmap, ...
                        Interpolation = "nearest", ...
                        DisplayRange = [0 8]);

                    % add image name to UIPanel title
                    app.Panel.Title = app.CLASS_FILE_NAME;

                else
                    % no files loaded
                    return
                end
                % close any useless figure panels that open
                close all
            catch ME
                message_text = "Encountered an error:" + ...
                    newline + "[ERROR MESSAGE]" +...
                    newline + ME.message;
                uialert(app.UIFigure,message_text,"Error")
                rethrow(ME)
            end

        end

        % Value changed function: OverlayOpacitySlider
        function OverlayOpacitySliderValueChanged(app, event)
            value = app.OverlayOpacitySlider.Value;
            app.IMAGE_VIEWER.Children.OverlayAlpha = value;
        end

        % Changes arrangement of the app based on UIFigure width
        function updateAppLayout(app, event)
            currentFigureWidth = app.UIFigure.Position(3);
            if(currentFigureWidth <= app.onePanelWidth)
                % Change to a 2x1 grid
                app.GridLayout.RowHeight = {480, 480};
                app.GridLayout.ColumnWidth = {'1x'};
                app.RightPanel.Layout.Row = 2;
                app.RightPanel.Layout.Column = 1;
            else
                % Change to a 1x2 grid
                app.GridLayout.RowHeight = {'1x'};
                app.GridLayout.ColumnWidth = {220, '1x'};
                app.RightPanel.Layout.Row = 1;
                app.RightPanel.Layout.Column = 2;
            end
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Get the file path for locating images
            pathToMLAPP = fileparts(mfilename('fullpath'));

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.AutoResizeChildren = 'off';
            app.UIFigure.Position = [100 100 640 480];
            app.UIFigure.Name = 'MATLAB App';
            app.UIFigure.SizeChangedFcn = createCallbackFcn(app, @updateAppLayout, true);

            % Create GridLayout
            app.GridLayout = uigridlayout(app.UIFigure);
            app.GridLayout.ColumnWidth = {220, '1x'};
            app.GridLayout.RowHeight = {'1x'};
            app.GridLayout.ColumnSpacing = 0;
            app.GridLayout.RowSpacing = 0;
            app.GridLayout.Padding = [0 0 0 0];
            app.GridLayout.Scrollable = 'on';

            % Create LeftPanel
            app.LeftPanel = uipanel(app.GridLayout);
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;

            % Create ImageFileNameField
            app.ImageFileNameField = uieditfield(app.LeftPanel, 'text');
            app.ImageFileNameField.Position = [116 294 100 22];

            % Create SelectImageButton
            app.SelectImageButton = uibutton(app.LeftPanel, 'push');
            app.SelectImageButton.ButtonPushedFcn = createCallbackFcn(app, @SelectImageButtonPushed, true);
            app.SelectImageButton.Position = [6 294 107 23];
            app.SelectImageButton.Text = 'Select Image';

            % Create ClassFileNameField
            app.ClassFileNameField = uieditfield(app.LeftPanel, 'text');
            app.ClassFileNameField.Position = [116 250 100 22];

            % Create SelectGLASSAIoutputButton
            app.SelectGLASSAIoutputButton = uibutton(app.LeftPanel, 'push');
            app.SelectGLASSAIoutputButton.ButtonPushedFcn = createCallbackFcn(app, @SelectGLASSAIoutputButtonPushed, true);
            app.SelectGLASSAIoutputButton.Position = [6 242 107 38];
            app.SelectGLASSAIoutputButton.Text = {'Select GLASS-AI'; 'output'};

            % Create LoadimagesButton
            app.LoadimagesButton = uibutton(app.LeftPanel, 'push');
            app.LoadimagesButton.ButtonPushedFcn = createCallbackFcn(app, @LoadimagesButtonPushed, true);
            app.LoadimagesButton.Position = [60 195 100 23];
            app.LoadimagesButton.Text = 'Load image(s)';

            % Create OverlayOpacitySliderLabel
            app.OverlayOpacitySliderLabel = uilabel(app.LeftPanel);
            app.OverlayOpacitySliderLabel.HorizontalAlignment = 'right';
            app.OverlayOpacitySliderLabel.Position = [64 47 91 22];
            app.OverlayOpacitySliderLabel.Text = 'Overlay Opacity';

            % Create OverlayOpacitySlider
            app.OverlayOpacitySlider = uislider(app.LeftPanel);
            app.OverlayOpacitySlider.Limits = [0 1];
            app.OverlayOpacitySlider.MajorTicks = [0 0.2 0.4 0.6 0.8 1];
            app.OverlayOpacitySlider.MajorTickLabels = {'0%', '20%', '40%', '60%', '80%', '100%'};
            app.OverlayOpacitySlider.ValueChangedFcn = createCallbackFcn(app, @OverlayOpacitySliderValueChanged, true);
            app.OverlayOpacitySlider.MinorTicks = [0.1 0.3 0.5 0.7 0.9];
            app.OverlayOpacitySlider.Position = [17 36 185 3];
            app.OverlayOpacitySlider.Value = 0.5;

            % Create Image
            app.Image = uiimage(app.LeftPanel);
            app.Image.Position = [6 331 208 143];
            app.Image.ImageSource = fullfile(pathToMLAPP, 'GLASS-AI Viewer Splash.png');

            % Create RightPanel
            app.RightPanel = uipanel(app.GridLayout);
            app.RightPanel.Layout.Row = 1;
            app.RightPanel.Layout.Column = 2;

            % Create Panel
            app.Panel = uipanel(app.RightPanel);
            app.Panel.Title = 'Panel';
            app.Panel.Position = [1 5 413 474];

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = GLASS_AI_viewer

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end