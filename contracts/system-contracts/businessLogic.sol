// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./AccesManagement.sol";

contract BusinessLogic is AccesManagement {

    struct Update {
        uint trainingAccuracy;
        uint trainingDataPoints;
        string weights;
    }

    struct Score {
        address trainer;
        uint256 score;
    }

    struct Trainer {
        address _trainerAddr;
        uint256 _reputation;
    }

    struct Task {
        uint taskId;
        string modelCID;
        string infoCID;
        //string testDataset;
        //uint256 requiredFinalAccuracy;
        address publisher;
        address[] trainers;
        string globalModelWeightsCID;
        uint currentRound;
        uint maxRounds;
        uint requiredTrainers;
        address[] registeredTrainers;
        string state;
    }


    uint256 _roundsDifference = 4;
    uint _scale = 1000000;
    uint256 _scaleRep = 1e18;
    uint256 _repScale = 1e26;


    // Registration Details
    mapping(address => bool) public registeredTaskPublishers;
    mapping(address => bool) public registeredTrainers;

    // here the rounds array elements corresponds to the end/finishing round before measuring the performance and updating the reputation
    // example trainer a => 2,4,6,12 => means that the trainer participated in rounds 0,1,2,3,4,5,10,11
    // assuming here that the rounds difference is 4 ie clients reselction occurs each 4 rounds
    mapping(uint => mapping(address => uint[])) public taskSelectedTrainers; // Task => trainer => rounds he has been involved in

    // Updates Details
    mapping(uint => mapping(uint => uint)) updatesCount; // task => round => number of Submited Updates
    mapping(uint => mapping(uint => mapping(address => bool))) updatesSubmitted; // task => round => Address => Bool
    mapping(uint => mapping(uint => mapping(address => Update))) public updates; // task => round => Address => Update

    // Reputation Details
    Trainer[] public accountsReputation; // address => reputation

    // Scores Details
    mapping(uint => mapping(uint => Score[])) public scores; // task => round => Score[]


    mapping(address => uint256) public balances;

    // Dynamic array to store tasks
    Task[] public tasks;



    constructor() {
    }

    // function to register a task publisher
    function registerTaskPublisher() public {
        require(!registeredTaskPublishers[msg.sender],"Task publisher already registered.");
        taskPublishers.push(msg.sender);
        registeredTaskPublishers[msg.sender] = true;
    }

    // Function to publish a task
    function publishTask(string memory _modelCID, string memory _infoCID, uint maxRounds, uint requiredTrainers) public {
        uint256 taskId = tasks.length; // Get the index of the newly added task
        tasks.push(Task({
                taskId: taskId,
                modelCID: _modelCID,
                infoCID: _infoCID,
                publisher: msg.sender,
                trainers: new address[](0),
                globalModelWeightsCID: "",
                currentRound: 0,
                maxRounds: maxRounds,
                requiredTrainers: requiredTrainers,
                registeredTrainers: new address[](0),
                state: "selection"
            })
        );
    }

    function registerTrainer() public {
        require(!registeredTrainers[msg.sender], "Trainer already registered.");

        trainers.push(msg.sender);
        registeredTrainers[msg.sender] = true;

        Trainer memory newTrainer;
        newTrainer._trainerAddr = msg.sender;
        newTrainer._reputation = 500000000000;

        accountsReputation.push(newTrainer);
    }

    // registers a trainer to a specific task
    function registerTrainerTask(uint _taskId) public {
        require(_taskId < tasks.length, "Task does not exist");
        require(registeredTrainers[msg.sender] == true, "the trainer is not registered in the bcfl system , he can't ask to join a task");
        Task storage task = tasks[_taskId];
        require(isInAddressArray(task.registeredTrainers, msg.sender) == false,"the trainer has already joined the task");
        task.registeredTrainers.push(msg.sender);
    }

    // assigns a trainer to a specific task
    function setTaskTrainers(uint _taskId, address[] memory taskTrainers) public onlyOwner {
        require(_taskId + 1 <= tasks.length, "Task does not exist");
        Task storage task = tasks[_taskId];
        require(task.publisher == msg.sender, "Only the publisher can select trainers");
        for (uint i = 0; i < taskTrainers.length; i++) {
            require(isInAddressArray(task.registeredTrainers, taskTrainers[i]) == true, "the trainer is not registered in the task");
            require(task.requiredTrainers > task.trainers.length, "Already reached required number of trainers , u can not be selected to this task to this task");
            task.trainers.push(taskTrainers[i]);
            if (task.trainers.length == task.requiredTrainers) {
                task.state = "training";
            }
        }
    }

    // set the trainers for a specific task for a specific time slot
    function setTaskRoundTrainers(uint _taskId, uint _round, address[] memory taskTrainers) public {
        require(_taskId + 1 <= tasks.length, "Task does not exist");
        Task storage task = tasks[_taskId];
        if (_round == 0) {
            tasks[_taskId].trainers = taskTrainers;
        }

        for (uint i = 0; i < taskTrainers.length; i++) {
            require(isInAddressArray(task.registeredTrainers, taskTrainers[i]) == true,"the trainer is not registered in the task");
            taskSelectedTrainers[_taskId][taskTrainers[i]].push(_round + 4);
            if (isInAddressArray(task.trainers, taskTrainers[i]) == false) {
                tasks[_taskId].trainers.push(taskTrainers[i]);
            }
        }
        task.state = "training";
    }

    // ida jak prblm later check this one
    function getTrainersForTaskRound(uint _taskId,uint _round) public view returns (address[] memory) {
        require(_taskId < tasks.length, "Task does not exist");
        address[] memory _roundChosenTrainers = new address[](tasks[_taskId].requiredTrainers);
        uint _index = 0;
        for (uint i = 0; i < tasks[_taskId].trainers.length; i++) {
            if (isInIntArray(taskSelectedTrainers[_taskId][tasks[_taskId].trainers[i]],_round + 4) == true) {
                _roundChosenTrainers[_index] = tasks[_taskId].trainers[i];
                _index++;
            }
        }
        return _roundChosenTrainers;
    }

    function getTrainersForTask(uint256 _taskId) external view returns (address[] memory) {
        require(_taskId < tasks.length,"Invalid task ID: Task does not exist.");
        return tasks[_taskId].trainers;
    }

    // I think hadi is enough
    function isTrainerForTask(uint _taskId,address addr) public view returns (bool) {
        require(_taskId < tasks.length, "Task does not exist");
        return isInAddressArray(tasks[_taskId].trainers, addr);
    }

    // all interactions except the current task
    function historicalInteractions(address _taskPublisher,address _addr,uint taskId) public view returns (uint256) {
        require(registeredTrainers[_addr] == true,"Trainer is not registered in the system");
        uint256 _totalInteractions = 0;
        for (uint i = 0; i <= tasks.length - 1; i++) {
            // u need to consider in each task the level of participation too
            if (tasks[i].publisher == _taskPublisher && isTrainerForTask(i, _addr) && tasks[i].taskId != taskId) {
                _totalInteractions += taskParticipationLevel(i, _addr);
            }
        }
        return _totalInteractions;
    }

    function taskParticipationLevel(uint _taskId,address addr) public view returns (uint256) {
        require(_taskId + 1 <= tasks.length, "Task does not exist");
        require(registeredTrainers[addr] == true,"Trainer is not registered in the system");
        uint256 _totalRounds = 0;
        for (uint i = 1; i <= taskSelectedTrainers[_taskId][addr].length; i++) {
            _totalRounds += _roundsDifference;
        }
        return _totalRounds;
    }

    // all the interactions a trainer had in the system including all the tasks
    function totalParticipationLevel(address addr) public view returns (uint256) {
        require(registeredTrainers[addr] == true,"Trainer is not register in the system");
        uint256 _total = 0;
        for (uint i = 0; i < tasks.length; i++) {
            if (isTrainerForTask(i, addr) == true) {
                _total += taskParticipationLevel(i, addr);
            }
        }
        return _total;
    }

    // total number of the tasks a trainer has participated in
    function totalNumberOfTasks(address addr) public view returns (uint256) {
        require(registeredTrainers[addr] == true,"Trainer is not register in the system");
        uint256 _totalTasks = 0;
        for (uint i = 0; i < tasks.length; i++) {
            if (isTrainerForTask(i, addr) == true) {
                _totalTasks += 1;
            }
        }
        return _totalTasks;
    }

    // total number of the tasks of a specific task publisher a trainer has participated in
    function totalNumberOfTasksWithPublisher(address addr,address _publisher) public view returns (uint256) {
        require(registeredTrainers[addr] == true,"Trainer is not register in the system");
        uint256 _totalTasks = 0;
        for (uint i = 0; i < tasks.length; i++) {
            if (tasks[i].publisher == _publisher && isTrainerForTask(i, addr) == true) {
                _totalTasks += 1;
            }
        }
        return _totalTasks;
    }

    // Count the number of tasks published by the given address
    function allTasksOfTaskPublisher(address addr) public view returns (uint[] memory) {
        uint count = 0;
        for (uint i = 0; i < tasks.length; i++) {
            if (tasks[i].publisher == addr) {
                count++;
            }
        }

        // Allocate memory for the _totalTasks array
        uint[] memory _totalTasks = new uint[](count);

        // Populate the _totalTasks array
        uint index = 0;
        for (uint i = 0; i < tasks.length; i++) {
            if (tasks[i].publisher == addr) {
                _totalTasks[index] = tasks[i].taskId;
                index++;
            }
        }

        return _totalTasks;
    }

    // Function to get all tasks
    function getAllTasks() public view returns (Task[] memory) {
        return tasks;
    }
    // Function to get a single task by its ID
    function getTaskById(uint256 taskId) public view returns (Task memory) {
        require(taskId < tasks.length, "Task does not exist");
        return tasks[taskId];
    }

    function submitUpdate(Update memory modelUpdate,uint task,address[] memory task_trainers,uint _round) public  {
        require(updatesSubmitted[task][_round][msg.sender] == false,"The sender already submitted updates for this running round");
        Task storage task_details = tasks[task];
        updates[task][_round][msg.sender] = modelUpdate;
        updatesSubmitted[task][_round][msg.sender] = true;
        updatesCount[task][_round]++;
        if (updatesCount[task][_round] == task_trainers.length) {
            task_details.state = "evaluation";
        }
    }

    function submitScore(uint _task,uint _round,Score[] memory _scores) public onlyOwner {
        for (uint i = 0; i < _scores.length; i++) {
            scores[_task][_round].push(_scores[i]);
        }
        Task storage task_details = tasks[_task];
        task_details.state = "aggregation";
    }

    function getRoundScores(uint _taskId,uint _round) public returns (Score[] memory) {
        Score[] memory _scores = new Score[](scores[_taskId][_round].length);
        for (uint256 i = 0; i < scores[_taskId][_round].length; i++) {
            _scores[i] = scores[_taskId][_round][i];
        }
        return _scores;
    }

    function getAllTrainers() public returns (address[] memory) {
        return trainers;
    }

    function getUpdatesForAggregationTask(uint taskId,uint _round) public onlyOwner returns (address[] memory, string[] memory) {
        address[] memory _roundTrainers = getTrainersForTaskRound(taskId,_round);
        string[] memory taskUpdates = new string[](_roundTrainers.length);
        for (uint i = 0; i < _roundTrainers.length; i++) {
            taskUpdates[i] = updates[taskId][_round][_roundTrainers[i]].weights;
        }
        return (_roundTrainers, taskUpdates);
    }

    function UpdateGlobalModelWeights(uint _taskId,string memory globalModelWeightsCID,string memory _state) public onlyOwner {
        require(_taskId + 1 <= tasks.length, "Task does not exist");
        tasks[_taskId].globalModelWeightsCID = globalModelWeightsCID;
        tasks[_taskId].currentRound++;
    }

    function updateTaskState(uint _taskId, string memory _state) public onlyOwner {
        require(_taskId + 1 <= tasks.length, "Task does not exist");
        Task storage task = tasks[_taskId];
        task.state = _state;
    }

    function getTaskState(uint _taskId) public returns (string memory) {
        require(_taskId < tasks.length, "Task does not exist");
        return tasks[_taskId].state;
    }

    function isInAddressArray(address[] memory arr, address look) public view returns (bool) {
    bool found = false;
     if(arr.length>0)    
          {    for (uint i = 0; i < arr.length; i++) {
      if (arr[i] == look) {
        found = true;
        break;
      }
    }}
    return found;
  } 

    function isInIntArray(uint[] memory arr,uint look) public view returns (bool) {
        bool found = false;
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i] == look) {
                found = true;
                break;
            }
        }
        return found;
    }

    function setReputation(address _addr, uint256 _newRep) public onlyOwner {
        for (uint i = 0; i < accountsReputation.length; i++) {
            if (accountsReputation[i]._trainerAddr == _addr) {
                accountsReputation[i]._reputation = _newRep;
                break;
            }
        }
    }

    function getReputation(address _addr) public onlyOwner returns (uint256) {
        uint256 _rep;
        for (uint i = 0; i < accountsReputation.length; i++) {
            if (accountsReputation[i]._trainerAddr == _addr) {
                _rep = accountsReputation[i]._reputation;
                break;
            }
        }
        return _rep;
    }

    function getAllReputations() public onlyOwner view returns (Trainer[] memory) {
        return accountsReputation;
    }

    function deposit() public payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        balances[msg.sender] += msg.value;
    }

    function getBalance(address _addr) public view returns (uint256) {
        return balances[_addr];
    }
}
